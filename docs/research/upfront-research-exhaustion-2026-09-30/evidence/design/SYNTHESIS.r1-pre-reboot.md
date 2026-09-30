# Certified Upfront Research (CUR): the synthesized protocol

Synthesis of `/tmp/rescomp/design/{frame-contract,statistical-stopping,reality-contact}.md` under the three judge
verdicts, 2026-09-30. **Spine: frame-contract** (the highest total from all three judges: strongest termination and
buildability). **Grafted:** reality-contact's evidence tiers, executable harness, contact skeleton, verdict vector and
rehearsal; statistical-stopping's carried seeds, W0 backtest, round-1 forecast, divergence diagnosis and blindness
engineering. Every fatal flaw the judges named is closed in §12.

New evidence produced for this synthesis (rerunnable, all under `/tmp/rescomp/design/`):
- `synth_stop.py` / `.out`: the stop rule below, simulated with realistic (partly undetectable) seeds, false positives
  that pass verification, and a hard cap.
- `synth_stop_split.py` / `.out`: residual split by stop reason.
- **Contact probe, this session** (positive control included):
  `cd /tmp && claude-latest -p '<quote the "Mission board" section or reply NONE>'` => `7 customer deliverable(s) are stale.`;
  the same call with `--setting-sources local` => `NONE`. So a headless Anthropic panel can run **without** the operator's
  resident instructions under OAuth. `--bare` also strips them, but it requires `ANTHROPIC_API_KEY` (`claude-latest --help`),
  and dollar spend is not authorized.
- `codex login status` => `Logged in using ChatGPT`. `gemini`, `pi` and `ollama` are on PATH; their auth has not been
  exercised.
- `bin/cc-decide` has no agent guard on `action` (grep for ancestry or an operator-only check: no hits). `bin/cc-signoff` is
  operator-only by ancestry, content-pinned, and a forgery advertises itself (`bin/cc-signoff:1-30`). **Ratification must
  therefore go through cc-signoff, not cc-decide.**

Paths without a root are relative to `/Users/chrisren/Development/claude-infrastructure`.

---

## 0. Diagnosis in five lines

1. The loop is not a shortage of research. Of 200 holes that surfaced after a "complete" claim, 3% were new operator requirements, 64.5% were desk-findable and 60% were misses inside a frame the research already had. The re-ask was simply the first adversarial audit (`taxonomy.md:9-18`).
2. "Complete" was measured against no denominator. The DoD carries the superlative verbatim (`hooks/dod-persist.sh`). REMAINDER counts `- [ ]` boxes that research DoDs never contain (`scripts/wrap-ledger.sh:616-623`). An absent DoD still renders ✅ (`:2286-2288`).
3. The machinery mandates new holes on every ask. Every gap-finder has a quota ("Find 2-3 gaps", `agents/deep-research.md:187`; "name 1-3 … MISSING", `agents/research-decomposition-critic.md:37`; "List 3", `skills/research-subagents/SKILL.md:798,823`). F1 passes any refinement under "nothing left on the table" (`CLAUDE.global.md:617`), and D4 forces every named item to be driven (`hooks/completion-assert.sh:1278`). So "No, one more thing" is the only compliant answer.
4. The checks ran after the claim and were regenerated on every ask. No persisted verdict, no materiality test, and no stop rule in code (OASIS is prose). "Are you sure?" flips answers 46% of the time (FlipFlop). Bounded passes over a frozen artifact converged (10→7→2); open fix-in-loop critics did not (23/21/24/28).
5. A literal "100.00/100.00 with zero unknowns" cannot be certified short of examining ≥95% of every place a hole could be (`stopping-rules.md` §2). What can be certified is **100.00% closure of a ratified frame plus a measured, stated residual, bought at a price chosen once**.

---

## 1. What the protocol promises, and the rulings it needs first

**"Research 100.00/100.00" means all of the following on one frozen snapshot, and nothing else:**
- (a) Every row of the operator-signed frame is closed with a receipt that a script checks. This part can be exactly 100.00.
- (b) Certification stopped under the pre-registered rule.
- (c) The certificate states the estimated material holes still present, with a 95% bound, and how many more desk rounds would find.
- (d) Every item research cannot reach (production traffic, a tenant we do not hold, elapsed time, the operator's eye) is declared, owned and dated.

**"No take-backs" means** that no signed row is reversed except through a typed, receipted, reproduced, material in-frame miss. Every such miss is counted and shown against the count the certificate forecast. New requirements, drift and declared residuals are typed events, not take-backs.

**"Finite" means** that every phase has a budget, and certification has a hard round cap ratified at intake. An overrun files a class-B packet whose default fires after 24 h, so the program cannot exceed its computed ceiling (§9.3) unless the operator acts.

Operator rulings required before first use. They replace stated practice, so each carries `Replaces: <practice> — ruling pending` until ruled.

| # | Ruling | Replaces | Recommendation | Conviction |
|---|---|---|---|---|
| AD1 | The definition above of "100.00", "no take-backs" and "finite" (a ratified frame, a stated residual, a hard cap with a default) | the unbounded "as long as it takes / 100.00" reading | adopt | 88%. The impossibility of the literal reading is proven; what remains open is whether a stated bound satisfies the operator |
| AD2 | Under a signed program, research is reopened only by an M1 (decision-changing) finding; M2/M3 go to the build backlog | Follow-On Gate F1 "nothing left on the table" (`CLAUDE.global.md:617`) | adopt | 85% |
| AD3 | completion-assert D4 ("drive every named item") is carved out for post-certification M2/M3 findings | `hooks/completion-assert.sh:1278` | adopt | 82% |
| AD4 | Remove the gap quotas from the three prompts | not an operator-stated practice | do it, no ruling needed | 92% |

AD1–AD3 go to the operator as **one class-C packet carrying the price table (§9.4)**, filed at W0 completion so it carries measured rather than simulated prices. Without AD1 nothing terminates: every anti-regeneration arm would read as moving the goalposts.

---

## 2. The protocol at a glance

| Phase | Locus | Work | Sub-gate (the phase `--goal`) | Prior budget |
|---|---|---|---|---|
| **P0 Intake and frame contract** | L (lead with operator; the exchange is the asset) | mining, interview, superlative translation, frame registers, bounded frame critique, signoff | G1 | 2 d, about 25 runs, 60–90 min of operator time |
| **P1 Census, premises, measure-first contact** | S | censuses by 2 methods; premise register; environment doctor; incumbent, ceilings and premise probes; handed-command dry runs | G2, G3 | 2 d, about 40 runs + probes |
| **P2 Decisions** | S (research waves) | options census, option probes, VOI-ordered and timeboxed D-rows, rulings or packets | G4, G5 | 3 d, about 40 runs |
| **P3 Executable spec and contact skeleton** | S (teammates for skeleton / harness / model check) | harness red on known-bad and green on known-good; skeleton across every environment boundary; fault injection | G6, G7 | 2.5 d, about 30 runs |
| **P4 Synthesis, freeze and seeding** | S (single integrator) | plan written from the ledgers; trace; store reconciliation; lint; fresh read; snapshot S₁; seeds planted | G8, G9, G12 | 0.5 d, about 8 runs |
| **P5 Certification rounds** | S per round-day, driving the `cur-round` Workflow | blind, seeded, cross-family panels; adjudication; fixes between rounds; forecast; stop rule | G13, G14 | forecast at round 1 (p50 about 7 rounds, about 3.5 d) |
| **P6 Rehearsal, sweep, gate, signoff** | S, then L for signoff | re-ask rehearsal; optional Fable sweep; `cc-research gate`; operator `cc-signoff` | G15–G17 | 1 d |
| **P7 Build-start revalidation** | S | freshness re-run; trunk and sibling check; carried rows routed to build waves | G10 at build start | 0.25 d |

**Only three loops are allowed:**
1. A refuted premise reopens only its dependency closure in P2 or P3.
2. P5 rounds, until the stop rule or the cap.
3. After the gate, a typed escape reopens only its dependency closure, with at most 2 delta rounds.

Nothing else loops. **Phase goals end at the agent's reach**, never on an operator-only conjunct (`docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md`):
`--goal 'cc-research gate --program <P> --phase P2 prints its verdict with every row PASS or FILED(<packet id>) — proven by the session running it and printing the output; do not edit frame.json; brief above, frame at docs/research/<P>/frame.json'`.

---

## 3. P0: intake and the frame contract

### 3.1 Mining before asking (read-only fan-out; output `intake-mined.md`, every claim quoted with a receipt)
- **Prior art:**
  - `docs/research/INDEX.jsonl` (built by `cc-research index`; 406 entries have no index today);
  - `docs/plans/**` in this repo and sibling repos;
  - `cc-memory-search <terms>`;
  - the transcripts `~/.claude*/projects/*/*.jsonl`, including subagent files (`<sid>/subagents/**`).
- **Operator history:**
  - `msg search` / `msg with` for every named counterparty (the in-person author agreement, hole 194);
  - `cc-decide list --all --json` (prior rulings such as the apex-domain decision, hole 186);
  - `cc-backlog list --all`, `cc-mission list`;
  - CLAUDE.md house rules that act as acceptance criteria (the one-command preference, hole 198).
- **Topic lock:** confirm there is no live owner, by a positive liveness signal (a commit minutes old, a live pane, open custody). Never declare an owner dead from absence (hole 139: three plans for one topic).

### 3.2 Interview: one sitting, 12 questions, each pre-filled from mining so the operator confirms or corrects
1. Who consumes the deliverable on day one, and how is it installed: agent, human or CI? (#198)
2. Where exactly does it run (host, OS or device, scheduler and interpreter, CI image, tenant, network)? What keeps it alive, what expires, and who re-authenticates? (#92, #96, the sevenrooms 9-day outage)
3. Which prior decisions, private facts, relationships, accounts and tenants bind it? (The agent lists what it mined; #147, #186, #194.)
4. What does "not lacking" mean? Give 3–5 positive references per taste axis and name who judges them. (#62, #65, #66)
5. What is explicitly out of scope, in your words? This is the only legitimate exit of the negative-space rule (`SKILL.md:800-803`), now answered up front.
6. Which actions are irreversible or spend money, and what must never regress? (#159, `b03a348`)
7. Which upstreams may move under us, and where could this be published or mirrored? (#181, #187)
8. What can only be verified in production or over time, and who owns that check?
9. What is the deadline, and what happens if it is missed (the negative branch)? (#179)
10. **Escape cost:** how many research days is one decision-changing hole found after build worth avoiding? This is the Dalal–Mallows c/f ratio and it picks the tier (§9.4). The contract summary states in words: *"c = ∞ means never deploy."*
11. Tier, absolute round cap R_abs and overrun default. Recommended: build tier, R_abs = 10, default proceed.
12. Which of your historical re-ask frames matter for this deliverable? They map to verdict axes (§3.6).

### 3.3 Superlative translation (port of `skills/ground-up/SKILL.md:14-18`)
Every superlative becomes one or more acceptance rows. Each row has:
- a predicate with a number;
- a ceiling measured first, as a P1 probe (hole 11: "maximally fast" was never compared with the engine's 0.14 s floor);
- a threshold;
- a negative-result branch;
- for taste, a positive reference set with the operator's eye as a dated gate.

Every hold carries an expiry (hole 56). `cc-research frame lint` refuses any predicate matching `perfect|100th|maximal|best|exhaustive|absolute|flawless` without a number. The operator's words are kept in `frame.json.intent_verbatim` and are never the predicate.

### 3.4 Frame registers and the Frame Axis Checklist
The registers are:
- **D** decisions: options must include do-nothing and use-what-exists;
- **Q** questions: each maps to at least one D-row, and a question that maps to none has zero value of information and is dropped;
- **X** axes;
- **C** coverage cells: question × axis;
- **K** censuses;
- **P** premises;
- **A** acceptance rows: the executable spec;
- **R** declared residual;
- **CU** certification units: ≤1,500 lines each, plus a **seam unit** for every boundary with a sibling plan.

The **Frame Axis Checklist (FAC)** lives in `docs/research/frame-axis-checklist.jsonl`. It is the frame-contract HPC-26 merged with the reality-contact 16 axes. Every contract maps each row to a register row, or marks it N/A with a reason. **Each post-gate frame defect adds a row.** Hole ids refer to `/tmp/rescomp/taxonomy_holes.py`.

| FAC | Axis the frame must carry | Holes |
|---|---|---|
| 01 | Option census including do-nothing and use-what-exists | 110, 120, 68 |
| 02 | Candidates enumerated from the artifact itself (repo, fork, installed), never from memory | 173, 69 |
| 03 | Upstream or base version as an explicit D-row; upstream tracker as an evidence source | 181, 182 |
| 04 | Instance census: every checkout, copy and deployed instance | 88, 102 |
| 05 | Caller and consumer census keyed by *name*, not path | 90, 44 |
| 06 | Execution-context matrix: deployment interpreter, scheduler, CI/build OS, real device | 92, 91, 95, 153, 41 |
| 07 | Liveness and expiry: what keeps it alive, what expires, who re-authenticates | 168, 96, 16, 170 |
| 08 | Concurrency and the fleet case: concurrent actors, N>1, generator-vs-UI races | 193, 126, 142 |
| 09 | Publication surfaces: mirrors, forks, jobs that push | 175, 187, 190 |
| 10 | Operator-owned accounts, tenants and devices | 147, 134 |
| 11 | Evidence beyond our own stores: access logs, trackers, the public web | 57, 111, 182 |
| 12 | Prior invariants, each with a guard test | 159, 141 |
| 13 | Handed commands run by the agent under the operator's real invocation (`!`, no TTY, launchd) | 155, 91, 156 |
| 14 | Platform and feature-support matrix | 33 |
| 15 | Deliverable consumer and install path | 198 |
| 16 | Operator-private relationships and agreements | 194, 107 |
| 17 | Hazard census: write paths to live data, destructive instruments, irreversibility | 10, 90, 126, `b03a348` |
| 18 | Seams with sibling plans: an owner for every producer and consumer | `LIMIT_RECOVER_100P.md:772-777` |
| 19 | Measured ceiling for every performance or superlative target | 11, 15 |
| 20 | Positive reference set for taste | 62, 65, 66 |
| 21 | Pre-registered thresholds and a negative-result branch | 179 |
| 22 | Every hold carries an expiry | 56 |
| 23 | Freshness: sibling trunk activity, registry releases, credential validity | 119, 165, 103, 164, 96 |
| 24 | Research probes never mutate the live subject | 49 |
| 25 | Compliance and data residency for external deliverables | 87 |
| 26 | Real artifacts, n>1, a load control | 191, 53 |
| 27 | Failure and recovery fault catalog (kill -9, quota death, network drop, reboot, partial write, TTL) | 191, 142 |
| 28 | Cost and quota of running the deliverable | 68 |

### 3.5 Materiality rubric: the single rubric used everywhere
A finding is **M1 (decision-changing)** only if it carries a locus (file:line or a verbatim quote), names a registered id, and does at least one of these:
- (a) changes a D-row's chosen option, or drops its conviction below 90;
- (b) changes an A-row's verdict or threshold, or shows the row cannot discriminate;
- (c) changes sequencing, an interface contract, or a cost or timeline figure by more than ±20%;
- (d) adds a census member that a D-row or A-row must cover, and that changes it;
- (e) moves a load-bearing premise outside its tolerance;
- (f) is a safety, security, data-integrity or irreversibility hazard. This is always M1: stop and surface.

The other levels:
- **M2** refinement: improves detail without meeting (a)–(f).
- **M3** cosmetic.
- **GENERIC**: no locus or no id. Logged and rejected.

**Classification is by vote plus reproduction:**
- 3 voters of mixed family (Opus, codex, gemini).
- M1 needs ≥2 votes, **and** a verifier reproducing the defect from the primary source with a probe receipt, **and**, for (a), an independent reproduction of the claimed flip.
- A split vote becomes **M2-disputed**. It goes to the build backlog with an audit flag and is re-judged against build evidence.
- Disagreement is never auto-promoted to M1. That promotion made statistical-stopping's gate unreachable, and false positives are the dominant LLM failure (FixedBench action bias 35–65%).

### 3.6 Verdict vector and re-ask frame map
The answer to any completeness question is a vector. Every historical frame maps to an axis or to a quoted exclusion. Counts come from the regex tally over the 88 asks in `/tmp/rescomp/loop_asks.json`, per `reality-contact.md` §3 I5.

| Axis | Computed from | Historical frames mapped (count) |
|---|---|---|
| V1 Research | gate + certificate | correct/complete/covering (59), researched/exhausted (24) |
| V2 Decisions outstanding | open and carried D-rows, operator-value packets | decisions/steps outstanding (15) |
| V3 Residual scheduled | `residual.jsonl`, with owners and dates | — |
| V4 Escapes since signoff | typed intake, against the certificate's forecast count | no take-backs/final (5) |
| V5 Loose ends | G12 store reconciliation, computed | no loose ends/follow-ons (9), reachable-environment slice (4) |
| V6 Built | harness rows green after build | all waves/master plan (4) |
| V7 Deployed and live | live content-read rows, not deploy status (the Denver lesson) | deployed and live (19) |
| V8 Optimum | ceilings measured and met | optimum / "nothing can beat it" (14) |
| V9 Session | the wrap-ledger rung | good to close/done (18), saved/persisted (4) |

### 3.7 Bounded frame critique: the only open-ended "what's missing?" in the protocol
- **Two pre-declared rounds**, each of **6 blind panels across ≥3 families**, with ≥1 non-Anthropic and Fable in ≤2 slots.
- The panels read the **registers and the census list, not the prose**, because critics audit what a plan says, not its unstated premises (`shard-7.md` pattern 1).
- Zero is an expected answer. Every proposed row cites a locus and the D-row it would change.
- The adjudicator dedups; the lead **integrates by Edit** (never appends).
- The FAC is applied mechanically.

The negative-space trigger runs **here and nowhere else**.

### 3.8 Ratification: operator-only and content-pinned
- The frame registers are landed on trunk.
- `cc-research frame render` produces a one-page summary covering:
  - register counts;
  - the definition of complete (§1);
  - the tier with its price table (§9.4);
  - R_abs and the computed ceiling;
  - the operator-owned dates;
  - the sentence "c = ∞ means never deploy".
- The operator runs `cc-signoff research:<P> --evidence <frame sha>`, a new `research:` mode of the existing tool (§11). It records `git rev-parse origin/main:<path>` for every frame file; one changed byte shows as reopened.
- The session DoD becomes one falsifiable line: `Scope (frozen): research program <P> frame v<n> (sha …) certified — proven by cc-research gate --program <P> exiting 0`.

---

## 4. The research loop (P1–P5)

### 4.1 Rules that hold in every phase
1. **No quotas. Zero is valid.** Every finding carries a locus, the id it would change, and a frame class.
2. **Discovery and certification are kept apart.**
   - Discovery (P1–P3, adaptive, directed, sees prior findings) finds and fixes. It **never** enters the estimation matrix (Böhme 2021).
   - Certification (P5) is blind, runs on a frozen snapshot, and only measures.
3. **Evidence tiers are computed, never typed.** Probes run only through `cc-research probe run`, which records the command, environment descriptor, stdin, n and raw output. The ladder:
   - E0 recall;
   - E1 secondary text;
   - E2 primary static read;
   - E3 live read with a TTL;
   - E4 measurement (n≥5, load control);
   - E5 target-environment execution;
   - E6 operator contact.

   The required tier follows `truth_lives_in`: code needs E2, current state E3, behavior E4, deployment behavior E5, and taste, intent or private facts E6. E0 and E1 never close a load-bearing claim.
4. **Probes are safe.** `mutates_live=false` or a sandbox (a throwaway label, sandbox HOME, `--dry-run`). A probe that must touch something live becomes `cc-backlog needs --run` (hole 49: a probe killed its subject).
5. **Everything persists in the project repo**, never in /tmp: 5 of 9 artifacts in one case lived only in /tmp (hole 76).
6. **Integrate, never append**, and the edit list is recorded, because "The integration is the generator" (`docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md:14`).

### 4.2 P1: census, premises and measure-first contact
- **Censuses.** Every population the FAC requires gets `census/<pop>.json`:
  - built from a generating command plus a **second, independent** method run by a different agent;
  - the union is reconciled;
  - it carries a coverage argument: how a missing member would show up.

  A blind non-Anthropic census critic names unlisted members, each needing a locus that proves it exists. **A census built from memory is inadmissible.**
- **Premises.** Every factual claim a D-row or A-row could rest on becomes a `premises.jsonl` row. Inherited findings enter at their original tier (usually E1) until probed, because 43 of 158 plan moves were "false when written" (`plan-lifecycle.md` §3). Every external fact gets a `recheck_cmd`, a TTL and `validated_at_sha`.
- **Measure-first contact wave** (the `cur-contact` Workflow, one slot per probe):
  - `cc-research probe-kit doctor`: interpreters, `env -i` scheduler emulation, OS version, container availability (the docker CLI panics today), cross-vendor CLI auth, credential expiry;
  - the incumbent measured with n≥5 and a load control;
  - every ceiling;
  - every risky premise at its required tier;
  - every handed command run by the agent with stdin at `/dev/null`;
  - credential and lock lifetimes.

  The exemplar is FLEET_V2 W0, after which W0–W6 landed in about 1.5 days. Contact runs **before** design because the problem statements were usually wrong: 10 of 12 constraint cells were later falsified (`plan-lifecycle.md` §5.3).

### 4.3 P2: decisions
- D-rows are researched in **value-of-information order** (Weitzman reservation value). Each gets a **timebox at intake**.
- `/research` waves (N 8–12) run with the zero-allowed brief. Every surviving option gets a probe or spike. `what_would_flip` is stated as a measurable condition and checked by a probe.
- **Rulings:**

| Condition | Route |
|---|---|
| ≥90% conviction with a receipt | agent rules; class-A record |
| <90% after exhaustive research, residue is framing, and weekly-Fable headroom exists | frontier ladder stage 2 (Fable writes a document), then back to Opus |
| <90% at the timebox, not an escalation surface | **class-B packet**: `--default <recommended option> --deadline <+48h> --conviction N --receipt R`. It defaults unless vetoed |
| <90% and it touches an escalation surface (auth, destructive migration, navigation, DB timeout) or an operator value (money, a customer relationship, irreversibility) | **class-C packet**. It never defaults. It is a **carried row**: it blocks only the build waves that depend on it, never the certificate, and it appears in V2 as a dated operator wait |

- Coverage cells close when **code-saturated** (topics named) **and meaning-saturated** (specified to implementation depth). Breadth arrives about 2× before depth (Hennink 2017).

### 4.4 P3: executable spec and contact skeleton
- **Acceptance harness** `docs/research/<P>/harness.sh`:
  - one row per A-row, echoing the command it ran and that command's own unpiped exit code;
  - `--self-test` must exit non-zero over `fixtures/known-bad/` and `--self-test-green` must exit 0 over `fixtures/known-good/`;
  - every row is classed with the DOCS_CONSOLIDATION §9 taxonomy (SOUND, NOT-A-COMMAND, ALREADY-PASSES, BLIND-TO-MECHANISM, FAILS-GREEN, MUTATES-STATE, BROKEN-SYNTAX), and only SOUND rows or labeled regression guards are admitted.

  **For a greenfield subject that does not exist yet, the known-bad fixture is the planted defect.** That gives "red on a planted defect" a meaning before build: it is the pattern of the one plan that closed and stayed closed (45 of 58 checks unsound before build, programme done in 25.75 h, never reopened).
- **Contact skeleton.** A throwaway worktree holding the thinnest end-to-end path, crossing **every** environment in the census once:
  - a **scheduler-initiated** launchd run under `/bin/bash` 3.2.57 (hole 92: it crashed on every trigger after a manual-run ✅);
  - the target build image, or an explicit degradation while docker is broken;
  - one real tenant call;
  - one real artifact through the pipeline;
  - handed commands with stdin at `/dev/null`.

  Its evidence is kept and its code is deleted.
- **State machines and concurrency** (FAC 08): an exhaustive small-scope enumeration script, which needs no Java or hypothesis. TLA+/hypothesis are used only if `probe-kit install` has run.
- **Fault injection:** one probe per fault-catalog member (FAC 27).
- **Production-scale n** where a synthetic rig reaches it (FLEET_V2 W5: 5- and 30-session rigs).

### 4.5 P4: synthesis, freeze and seeding
1. The plan is written **from** the ledgers by a single integrator.
2. `cc-research trace check`: every finding id in every research artifact maps to a plan anchor or a recorded rejection. It targets the dropped warm-connection fix (#172) and the 744-line axis read by its headline only (#61).
3. `cc-research reconcile`: plan-prose open markers, research residual sections, backlog, open decisions, custody and dirty files are each mapped to done, not-required-with-reason, filed, or a row (C1).
4. `cc-research lint`: numbers consistent across sections, no superseded values, anchors resolve, no /tmp paths, no numberless superlatives.
5. A **fresh-context whole read** after the last edit, recorded as a probe (#180: a script-assembled plan held 20 defects).
6. **Freeze** snapshot S₁. From then on, edits happen only between certification rounds.
7. **Seeding** (§4.6.4): the seed author plants the original cohort into the sealed copy; realism is tested once.

### 4.6 P5: certification rounds

#### 4.6.1 Panel composition (T = 8 per round; ≥3 families; ≥1 non-Anthropic)

| Slots | Family | Invocation (cwd = the sanitized bundle; read-only) | Strategy |
|---|---|---|---|
| 2 | Opus 5.5 | `claude -p --setting-sources local --allowedTools "Read Grep Glob" --permission-mode dontAsk --model <Opus-5.5-capable id>` | full bundle; adversarial "assume it fails in production" |
| 2 | OpenAI | `codex exec -s read-only` | full bundle; spec-only (plan without the registers) |
| 2 | Google | `gemini -p … --approval-mode plan` | full bundle; consumer perspective |
| 1 | Opus 5.5 | as above | spec-only |
| 1 | Fable 5.1 in rounds 1, 3 and 5, else Opus | as above with `--model claude-fable-5-1` | adversarial |

- Every panel is a **CLI process launched by a courier slot** of the `cur-round` Workflow. The courier relays raw output verbatim and never filters it. Anthropic panels therefore run without the operator's resident instructions, per this session's `--setting-sources local` probe. That closes the judges' contamination flaw: global CLAUDE.md, rules and the mission board carry lessons that match escape seeds, and program findings. Auto-memory is empty because the cwd is a new path.
- **Two premises are unverified and are W0 checks:**
  - that `--setting-sources local` strips the same way on the binary that runs Opus 5.5 (`claude-latest` stays on 2.1.114, which cannot run Opus 5.5; memory `headless-trial-arm-model-from-init-line.md`);
  - that `dontAsk` refuses a Read outside the cwd.
- **Fable accounting.** Headless runs under `--setting-sources local` load no user hooks, so `frontier-spawn-gate.sh` cannot be assumed to see them. `cc-research panel run` therefore counts Fable panel-runs against the program's ratified Fable cap (default 8) in `budget.json`, checks `claude-accounts` weekly-Fable headroom first, and substitutes an Opus spec-only slot on refusal. The substitution is a degradation printed on the certificate.

#### 4.6.2 Blindness engineering
- **Sanitized bundle:**
  - `git archive <trunk_sha>`, extracted into `~/.claude/autonomy/research/<P>/vault/r<k>/bundle/`, so there is **no .git and no history**;
  - `docs/research/<P>/`, `.claude/` and every `CLAUDE.md` are removed;
  - the seeded plan and registers are copied in.
- **Seeds are encrypted at rest** (`openssl enc -aes-256-cbc`, with the key in the login keychain) and are decrypted in memory only by `cc-research seed apply|match`. An incidental grep finds ciphertext.
- **Integrity audit after every round.** Panel transcripts and outputs are grepped for the real program path, the vault seed path and `git log`. **A hit voids the panel**, and the round needs a re-run. The limit is stated honestly: a same-UID codex or gemini process can still read the real repo, so this half is detection, not prevention.
- **Every panel prompt carries the snapshot sha and the seeded-bundle hash.** The Workflow resume cache key has no tree term (`docs/research/workflows-vs-teams-2026-08-20.md:364-367`).

#### 4.6.3 Panel brief (frozen; identical for all T panels)
> Audit the FROZEN bundle in your cwd against `frame.json`. Read-only. You will not see other reviewers' or earlier findings.
> Part 1: for each A-row and D-row in scope answer YES / NO / UNKNOWN, each with a receipt (a file:line you read). No receipt ⇒ UNKNOWN.
> Part 2: for each of the 11 lenses (premise, census, instrument, trace, consistency, sequencing, criteria, contact declaration, drift, frame-omission, operator-intent), write what you checked, then either findings or "nothing material".
> **Zero findings is a correct and expected outcome. You are not rewarded for finding something.**
> Each finding must carry: (a) a locus; (b) the D/A id it changes and how, or the sequencing/interface/cost figure it moves >20%, or the hazard; (c) the read receipt; (d) your probability that it is real and material, plus the observation that would falsify it.

A dead or partial panel is re-run once. If it is still dead the round is void, and it counts neither dry nor wet (C8: "three dead critics read as no gaps").

#### 4.6.4 Seeds: carried cohorts, anchored patches, censoring
- **Format.** A seed is a patch anchored on a verbatim quote: `{sid, cohort, class, file, anchor_quote (≥40 chars, unique), replacement, defect_statement, detect_span}`.
- **Application.** `cc-research seed apply` re-applies every **uncaught** seed to each new snapshot S_k, so the lead edits the tracked, unseeded plan and never sees seeds.
- **Orphans.** If a fix changed the anchor, so it is absent or no longer unique, the seed is **orphaned**: censored at round k, removed from its cohort's denominator, counted neither caught nor surviving. This closes the judges' "carried seeds have no mechanics across edits" flaw.
- **Original cohort.** s₀ = 60 at S₁ (build tier), capped at 1 per 25 bundle lines. It is stratified by the desk-findable class mix in `taxonomy_stats.py` (C4 29, C3 26, C1 23, C5 13, C6 12, C7 8, C8 8, C11 4, C10 3), using statistical-stopping's per-class mutation operators (`statistical-stopping.md` §5.3).
- **Fix cohorts.** After each round with fixes, ⌈0.5 × fixes⌉ new seeds (minimum 3) are planted **inside that round's edited spans** and carried from then on. Fix-born holes (C7) are young and live in edited spans, and the cohort mirrors exactly that.
- **Escape seeds.** 20, stratified by class. They transplant historical escape *mechanisms* from `docs/research/escape-library/escapes.jsonl`. They form a **hard-tail recall gate, never a denominator** (as a denominator they overestimate about 2.5×, `unseen-estimation.md` §5 row I). Recall is reported **per family**; Anthropic recall far above non-Anthropic recall on escape seeds but not on representative seeds flags contamination.
- **Realism, bounded.** Once, at S₁, a third-family discriminator judges 20 blind (seed span, real span) pairs. Accuracy above 0.70 means the seeds are rewritten **once**. A second failure prints "seed realism failed; residual estimate unreliable" on the certificate. It never loops.
- **Caught.** A panel finding whose locus overlaps a seed's `detect_span` and whose claim matches is caught (script plus one seed-aware judge). A caught seed is removed from later rounds, exactly like a fixed hole.

#### 4.6.5 Adjudication, verification, fixes
1. **Adjudicator** (Opus xhigh, blind to panel identity, detection counts and seeds): clusters findings into candidate holes and logs every merge and split.
2. **Second adjudicator** (codex) on a 20% sample plus **every singleton**. Agreement is reported. Below 0.6, adjudication is re-run once with the rubric clarified, and a second failure prints "adjudication unstable".
3. **Verifier:** reproduces each candidate through `probe run`, blind to how many panels found it. Singletons are verified, **never culled** (Deng 2024).
4. **Materiality vote** (§3.5).
5. **Fixes.** Verified M1 holes are fixed by the lead **between rounds** by integration. A fresh consistency reader then reads the edited spans and their dependents. Its finds are discovery and never enter the matrix.
6. **M2/M3 are not integrated.** They go to the build backlog (`cc-backlog add --why-not-now "not-yet-true: build wave <n>" --dod-ref …`), so refinements cannot generate fix-born holes.

#### 4.6.6 Estimators (`cc-research estimate`; each with a planted-input test that must go red)
- **Residual.** For each cohort c: π̃_c = (k_left,c + 0.5)/(s_eff,c + 1), with π_up,c its Clopper–Pearson 95% upper bound. Then:
  - μ̂ = Σ_c F_c·π̃_c/(1−π̃_c), where F_c counts verified M1 real holes attributed to that cohort's population: original, or `born_in_edit` for fix cohorts;
  - μ_up = the same sum with π_up,c;
  - **n_pred95** = the Poisson 95% quantile at μ_up;
  - P(≥1 material left) ≈ 1 − e^(−μ̂).
- **Yield of more search:** ρ̂ = seeds caught ÷ seed-rounds at risk over the last K rounds, and E[found by m more rounds] = μ̂·(1 − (1 − ρ̂)^m). This prices `extend`.
- **Cross-checks on every non-dry round:** Chao2 (bias-corrected), JK2, per-family Chao2, and the **family × family co-detection matrix**. No published measurement of LLM correlation on design review exists, so this matrix is recorded to `docs/research/research-calibration.jsonl`.
- **Fix-born rate:** b̂ = verified M1 found in round k+1 inside round k's edited spans ÷ fixes in round k.

#### 4.6.7 Forecast after round 1, and the divergence rule
- The inputs:
  - N̂₀ = max(Chao2, JK2) of the round-1 M1 matrix;
  - R̂ = original-cohort recall in round 1;
  - b̂ starts at 0.1;
  - q̂ = (1 − R̂) + b̂R̂.
- p50 rounds ≈ ⌈ln(N̂₀/0.5)/ln(1/q̂)⌉ + K. `cc-research forecast` also simulates the `synth_stop.py` model with the fitted N̂₀, R̂ and b̂ to get p50/p90.
- **R_max = min(p90 + 2, R_abs)**, fixed after round 1 and printed with a date.
- **Divergence:** if b̂ ≥ 0.5·R̂ at round 3 or later, the fixes are generating holes (the 23/21/24/28 regime). The next inter-round step must **delete machinery or restructure the offending CU** (a `/ground-up` of that unit), not add more. That step spends rounds from the same R_max and never extends it.

#### 4.6.8 The stop rule (the only one)
**Stop at the end of round r ≥ 2 when the last K rounds were dry, meaning 0 new verified M1 items, real or false: `stop=dry`. Otherwise stop when r = R_max: `stop=cap`.** A dry round makes no edits, so the K dry rounds run on the same snapshot.

Why this rule, from the simulation. `synth_stop.out` uses 800 reps per row, N₀ = 60 material holes at the first freeze, 5% of real holes invisible to every family, seeds with the same 5% share, and 0.25 false-positive M1 items per round passing verification:
- **Termination is guaranteed.** At K = 2: rounds p50 7, p90 8, max 9.
- **The stated bound is calibrated.** P(total left ≤ n_pred95) = 1.000. μ̂ median 4.49 against a true total-left mean of 4.16.
- **The cap costs nothing measurable** (`synth_stop_split.out`, K = 2, fp 0.25). Programs stopped by the cap ended with desk-detectable residual 0.59 (P≥1 = 0.44), against 0.73 (0.50) for programs stopped dry, because the cap-stopped ones ran more rounds. There is therefore **one verdict, CERTIFIED, with the stop reason printed**, and no decision packet at the cap. The operator ratified R_abs in advance.
- **Seeds with no undetectable share state only the detectable residual.** μ̂ median 1.37, and the bound covers total-left 0.960, not 1.000. Seed difficulty must match the real difficulty law, and only W0 can check that.

### 4.7 P6: rehearsal, sweep, gate, signoff
- **Re-ask rehearsal: once, bounded.** 12 blind sessions from the same courier families. Each gets **one historical frame as a lens** (e.g., "deployed and live", "nothing can beat it"), the certified bundle and the verdict render. The operator's literal challenge wording is never used, because FlipFlop measured "are you sure?" flipping 46% of answers. Each answer is typed:
  - the frame is answered by axis Vn;
  - or the frame is unmapped, which becomes a class-B packet (default: exclude, quoting intake Q12);
  - or an in-frame M1 with a locus, which goes through §3.5.

  A verified M1 is fixed, then **one** further full round (K = 1) runs. If that round is not dry, its finds are fixed and the stop is recorded as `cap`.
- **Fable sweep**, optional, only with headroom. Two baseline-blind `frontier-derivation` panelists read the certified bundle. NEW material items go through the typed intake. If NEW M1 exceeds n_pred95, a **calibration breach** is flagged.
- **Gate.** `cc-research gate --program <P>` computes G1–G17 (§6). Then the operator runs `cc-signoff research:<P>` over the certificate, the frame and the residual hashes.
- **Build fires only on CERTIFIED**, enforced by `handoff-fire.sh --requires-gate <P>`. That prevents a repeat of hole #137, where W1 fired while research slots r4 and r7 were open. Carried rows block only their dependent waves.

### 4.8 P7: build start
`cc-research premise due` re-runs every premise whose TTL expired or whose `depends_on_paths` changed since `validated_at_sha`. It also re-reads trunk and siblings for the topic and re-checks credentials. A changed dependent is **drift** (§8), revalidated in scope.

### 4.9 Roles

| Role | Who | Rule |
|---|---|---|
| Program lead | Opus 5.5 high, one dispatched session per phase | holds the ledgers; integrates; never adjudicates, sees seeds, or judges its own completeness (the gate script does) |
| Miners, census-takers, probers | `workflow-lean` slots, Opus medium | probes only through `probe run`; two census methods by different agents |
| Frame, census and premise critics | Fable plus one non-Anthropic | read registers, not prose; zero-allowed |
| Harness author / control verifier | two different agents | the verifier plants the defect and sees red; the author never self-certifies |
| Seed author | a family other than the panel majority, in a separate session | writes encrypted seeds; never a panelist |
| Panels | §4.6.1 | blind, sanitized, courier-relayed |
| Adjudicators, verifier, materiality voters | §4.6.5 | blind to counts and identity |
| Gatekeeper | `cc-research gate`: **code, not a model** | deterministic predicates; UNKNOWN fails |
| Operator | the human | interview, frame signoff, class-C rulings, E6 gates, final signoff |

---

## 5. Artifacts and schemas

**Project repo** `docs/research/<P>/` holds the tracked files. JSON is used because the model is less likely to rewrite it (`llm-failure-modes.md` T2). Stores are append-only event logs, and state is the fold. Markdown is rendered and never hand-edited.

```
frame.json  FRAME.md  intake.md  intake-mined.md
decisions.jsonl  coverage.jsonl  census/<pop>.json  premises.jsonl  facts.jsonl
probes.jsonl  evidence/<probe-id>/{cmd,stdout,stderr,env.json}
acceptance.json  harness.sh  fixtures/{known-bad,known-good}/  residual.jsonl  trace.jsonl
holes.jsonl  rounds/<k>/matrix.json  rounds/<k>/panels/<pid>.json
cert/CERT-v<n>.{json,md}  verdicts.jsonl  changes.jsonl  budget.json
```

**Global:**
- `~/.claude/autonomy/research/programs.json`: the registry mapping program → repo, status and certificate path. It lets the re-ask hook work from any cwd.
- `~/.claude/autonomy/research/<P>/vault/` (mode 0700): encrypted seeds, bundles, per-round panel transcripts. Hashes are committed into `matrix.json`.

**Cross-program, tracked in claude-infrastructure:**
- `docs/research/INDEX.jsonl`
- `docs/research/frame-axis-checklist.jsonl`
- `docs/research/escape-library/escapes.jsonl`
- `docs/research/research-calibration.jsonl`: actuals, the family matrix, escapes against forecast.

```jsonc
// frame.json (frozen; the sha is pinned by cc-signoff research:<P>)
{ "program": "slug", "version": 3, "intent_verbatim": "…", "deliverable": "one sentence, numbers, no superlatives",
  "consumer": {"who": "", "installed_by": "agent|human|ci", "runs_where": "env id"},
  "axes": [{"id": "X-06", "fac": "FAC-06", "status": "in|excluded", "exclusion_quote": null, "rows": ["A-17"], "populations": ["K-03"]}],
  "fac_map": [{"fac": "FAC-24", "row": "N/A", "reason": "no live subject"}],
  "cus": [{"id": "CU-2", "spans": ["PLAN.md:1-1400"]}, {"id": "CU-seam-1", "between": ["this", "SIBLING_PLAN.md"]}],
  "reask_map": [{"frame": "deployed and live", "axis": "V7"}],
  "materiality": {"rubric": "CUR-1"},
  "tier": {"name": "build", "T": 8, "K": 2, "s0": 60, "escape_seeds": 20, "R_abs": 10, "fable_cap": 8,
           "families_min": 3, "non_anthropic_min": 1, "c_over_f_days": 3},
  "budget": {"phase_days": {"P0": 2, "P1": 2, "P2": 3, "P3": 2.5, "P4": 0.5, "P6": 1}, "overrun_factor": 1.5,
             "overrun_default": "proceed", "overrun_deadline_h": 24},
  "residual_allowed": ["production-traffic", "external-tenant-not-held", "elapsed-time", "operator-eye"],
  "operator_dates": [{"what": "rule D-07", "due": "YYYY-MM-DD"}],
  "trunk_sha_at_ratify": "…", "signoff": {"id": "", "sha256": "", "at": ""} }

// decisions.jsonl
{ "id": "D-04", "question": "", "type": "fact|design|taste", "options_census": "census/options-D-04.json",
  "options": [{"label": "do-nothing", "probe": "P-.."}, {"label": "use-what-exists", "probe": "P-.."}],
  "premises": ["PR-031"], "chosen": "", "conviction": 92, "receipt": "", "what_would_flip": "", "flip_checked_by": "P-..",
  "voi_rank": 3, "timebox_d": 1, "ruled_by": "agent|ladder|operator|packet-default", "packet": {"id": "", "class": "A|B|C"},
  "escalation_surface": false, "operator_value": false, "status": "open|ruled|carried|reopened", "affects": ["PLAN.md§4"], "ts": "" }

// premises.jsonl
{ "id": "PR-031", "claim": "", "load_bearing_for": ["D-04", "A-17"], "truth_lives_in": "code|live-state|behavior|target-env|operator",
  "required_tier": "E2..E6", "achieved_tier": "computed from probes", "origin": {"source": "", "tier": "E1"},
  "probes": ["P-044"], "verdict": "holds|refuted|partial|unknown", "tolerance": "",
  "validated_at": {"ts": "", "trunk_sha": "", "depends_on_paths": [""]}, "ttl_h": 72, "recheck_cmd": "" }

// probes.jsonl (written only by `cc-research probe run`)
{ "id": "P-044", "closes": ["PR-031"], "kind": "read|live-read|measure|spike|skeleton|model-check|fault-inject|handed-cmd|read-through|reproduce|operator-view",
  "env": {"id": "launchd-bash32", "descriptor": {"interpreter": "/bin/bash 3.2.57", "PATH": "/usr/bin:/bin", "os": "15.7.9"}},
  "cmd": "", "stdin": "/dev/null", "n": 5, "load_control": true, "falsifier": "", "raw": "evidence/P-044/",
  "exit": 0, "mutates_live": false, "sandbox": "none|sandbox-HOME|dry-run|throwaway-label", "trunk_sha": "", "at": "" }

// census/<pop>.json
{ "population": "", "methods": [{"agent": "", "cmd": "", "count": 0}, {"agent": "", "cmd": "", "count": 0}],
  "members": [{"id": "", "source_line": ""}], "reconciled_diff": [], "coverage_argument": "",
  "critic": {"family": "openai", "unlisted_verified": 0}, "validated_at": {"ts": "", "sha": ""} }

// acceptance.json (rows)
{ "id": "A-17", "axis": "X-06", "predicate": "plain sentence with a number", "check_cmd": "", "env": "",
  "threshold": {"metric": "", "op": "<=", "value": 0, "ceiling_probe": "P-.."}, "expect_prebuild": "RED|GREEN-guard",
  "control": {"known_bad": "fixtures/known-bad/..", "red_proof_probe": "P-..", "known_good": "fixtures/known-good/.."},
  "n": 5, "soundness": "SOUND|…", "premises": [], "decisions": [], "status": "sound|carried|reopened" }

// holes.jsonl (event log; seeds are revealed only after adjudication)
{ "id": "H-041", "event": "raise|adjudicate|verify|vote|dispose|reopen", "round": 3,
  "source": "panel|rehearsal|sweep|discovery|consistency|challenge|build|operator",
  "raised_by": {"panel": "r3p5", "family": "openai", "blind": true, "snapshot_sha": ""},
  "locus": {"path": "", "lines": "", "quote": ""}, "names": ["D-04"], "cu": "CU-2",
  "materiality": {"level": "M1|M2|M2-disputed|M3|GENERIC", "votes": ["M1", "M1", "M2"], "flip_repro": "P-.."},
  "verification": {"status": "CONFIRMED|REFUTED|CONTACT", "probe": "P-.."}, "seed_match": null,
  "frame_class": "in-frame-miss|frame-defect|frame-expansion|relabel|contact-residual|drift|immaterial",
  "taxonomy_class": "C1..C11", "born_in_edit": false, "reopen_set": [],
  "disposition": {"kind": "fixed|build-backlog|residual|cr|rejected|duplicate", "ref": ""}, "ts": "" }

// rounds/<k>/matrix.json (no seed content: ids and detections only)
{ "round": 3, "snapshot_sha": "", "bundle_hash": "", "panels": [{"pid": "r3p1", "family": "anthropic", "model": "", "status": "complete|void"}],
  "dry": false, "m1": [{"id": "H-041", "x": [0,1,0,0,0,1,0,0]}],
  "seeds": {"orig": {"s_eff": 58, "k_left": 7, "orphaned": 2}, "fix": [{"cohort": "fix-r2", "s_eff": 4, "k_left": 1}],
            "escape_by_class_family": {"C4": {"anthropic": [2,3], "openai": [1,3]}}},
  "est": {"mu_hat": 0, "mu_up": 0, "n_pred95": 0, "p_ge1": 0, "rho_hat": 0, "extend_yield": {"1": 0, "2": 0},
          "chao2_bc": 0, "jk2": 0, "per_family_chao2": {}, "codetect": [[0]], "b_hat": 0},
  "forecast": {"N0_hat": 0, "R_hat": 0, "p50": 0, "p90": 0, "R_max": 0}, "adjudication_agreement": 0.0,
  "integrity": {"grep_hits": 0}, "sealed_hashes": {} }

// verdicts.jsonl: every completeness question and what answered it
{ "ts": "", "session": "", "cwd": "", "question": "", "program": "P", "answered_with": "CERT-v3|H-..|CR-..",
  "vector": {"V1": "CERTIFIED", "V2": "1 carried", "V4": "0 escapes / forecast 4.4"}, "take_back": false, "cause": null }

// changes.jsonl: every post-freeze change, each with a cause
{ "id": "CR-3", "cause": "operator_new|operator_unelicited|frame_defect|reality_moved|escape",
  "artifact": "", "span": "", "hole": "H-..", "delta_rounds": ["d1"], "resigned": "signoff id|null" }

// residual.jsonl
{ "id": "RS-3", "property": "", "why_unreachable": "production-traffic|external-tenant-not-held|elapsed-time|operator-eye",
  "closest_probe": "P-..", "verify_cmd": "", "owner": "agent|operator", "due": "", "backlog_id": "", "falsifier": "",
  "reopens_on_fail": ["A-.."] }
```

---

## 6. The exit gate: exact criteria

`cc-research gate --program <P> [--phase Pn]` prints `G<n> PASS|FAIL|FILED <evidence>` and exits 0 only when every row is PASS or FILED. Every predicate reads the ledger and re-executes what it names in this run. UNKNOWN fails.

| Gate | Criterion (all must hold) |
|---|---|
| **G1 Frame** | `sha256(frame.json)` equals the cc-signoff pin. Every FAC row is mapped or N/A with a reason. Every axis is in scope or excluded with a quote. 0 numberless superlatives. Every re-ask frame from intake Q12 is mapped. 0 open change requests |
| **G2 Census** | Every FAC-required population has a census with **≥2 independent methods**. The generating commands, re-run now, reproduce the member set, and any diff is dispositioned. Every option census has do-nothing and use-what-exists. The census critic's verified-unlisted count is 0 |
| **G3 Premises** | Load-bearing premises with achieved tier below required tier: **0** (computed from `probes.jsonl`). Premises with verdict `unknown`: 0. Every refuted premise's dependents are REVISED. All premises are within TTL |
| **G4 Decisions** | Every D-row is `ruled` (agent at ≥90 with `what_would_flip` probe-checked; ladder; operator; or class-B `expired-actioned`) **or** `carried` (class C, dated, blocking only its dependent waves). Carried rows are listed on the certificate |
| **G5 Coverage** | Every cell is code- **and** meaning-saturated with existing evidence paths, or N/A with a reason recorded at ratification |
| **G6 Instruments** | This run: `harness.sh --self-test` exits ≠0 over known-bad **and** `--self-test-green` exits 0 over known-good. 0 non-SOUND rows (except labeled guards). Every row has a red-proof probe. Timing rows have n ≥ 5 with a load control |
| **G7 Contact** | Every environment in the census is crossed by ≥1 skeleton, measure or dry-run probe carrying its env id. Every scheduled component has ≥1 **scheduler-initiated** run. Every handed command was executed by the agent with stdin at `/dev/null`. Environments the tooling cannot reach are listed as degradations |
| **G8 Trace and persistence** | `trace check`: 0 unmapped findings. 0 cited paths outside the repo. Every evidence path exists at the snapshot sha. The index search is recorded. The topic lock is positive |
| **G9 Integrity and freeze** | `lint` finds 0 errors. A fresh read-through probe after the last edit found 0 M1. The certifying snapshot sha equals the plan sha. There is no post-freeze edit without a following round |
| **G10 Freshness** | Every `recheck_cmd` was re-run within 24 h. Trunk commits since `validated_at_sha` touching any `depends_on_paths` are dispositioned. Credentials are valid for the build window plus 7 days |
| **G11 Residual** | Every residual row has an allowed `why_unreachable`, a closest probe already run, a verify command, an owner, a due date, and a backlog id with a falsifier. `probe-kit doctor` confirms each environment is not locally emulable |
| **G12 Store reconciliation** | 0 unmapped items across plan prose markers, research residual sections, `cc-backlog list --project`, `cc-decide list --open` for the project, custody and dirty files |
| **G13 Panels** | Every counted round has 8 complete panels, ≥3 families and ≥1 non-Anthropic. Integrity grep hits: 0. Void panels were re-run or the round was voided |
| **G14 Stop** | `stop=dry` (the last K = 2 rounds had 0 verified M1, with r ≥ 2) **or** `stop=cap` (r = R_max = min(p90 + 2, R_abs), fixed and dated after round 1). Estimates are written: μ̂, μ_up, n_pred95, P(≥1), extend yield, family matrix |
| **G15 Hard tail** | Escape-seed recall ≥ 0.5 in every class with ≥3 escape seeds. For a class below that, **one** structural detector (a census row, a lint, a probe) is added and re-checked on the class's seeds. If it is still below, the certificate prints the class as a **named weak lens**. There is no second attempt |
| **G16 Rehearsal** | 12 of 12 frames typed. 0 unmapped frames without a disposition. Any verified in-frame M1 was fixed and followed by one full round |
| **G17 Budget** | Actual against forecast per phase is recorded. Every overrun has a packet, and every packet is resolved or expired-actioned. Informational only: it never blocks |

**Verdict states:**
- **CERTIFIED**: G1–G17 pass. The stop reason, carried rows, degradations and weak lenses are printed.
- **NOT CERTIFIED**: some gate row is still in work inside its phase budget.
- **STALE**: a post-issue freshness re-check failed.

**Overrun (the only other terminal route).** A phase at 1.5× its budget files `cc-decide open --class B --what "Phase P<n> of <P> is at 1.5x budget: <open rows>" --option "extend::<N> more runs" --option "proceed::open rows become carried rows with owners and dates" --default proceed --deadline <+24h> --conviction N --receipt <gate output>`. On `expired-actioned`, the open rows become carried rows. So the program **always** reaches CERTIFIED, stating what it carries, unless the operator vetoes.

**The certificate** (`cc-research verdict --render`; the numbers are illustrative):
```
Research: CERTIFIED (stopped: 2 dry rounds). Program <P>, frame v3 signed 10-12 (sha a1b2…), snapshot 9f8e…, trunk <sha>, 10-19 14:05.
Frame 100.00% closed: 18/18 decisions ruled (1 carried: D-07 awaits your call, due 10-21) · 64/64 cells · 11/11 censuses, 2 methods each ·
  41/41 acceptance rows sound, red-first, re-run 10-19 · 72/72 premises at required tier · 12/12 of your question frames mapped.
Certification: 7 rounds × 8 blind reviewers, 4 model families; 38 decision-changing holes found and fixed; last 2 rounds found 0.
Estimated still present: 4.4 decision-changing holes (95% bound ≤ 16). About 0.3 of them would be found by 2 more rounds; the rest are
  a kind no desk reviewer catches, which the contact checks and the dated post-build checks below exist for. Seeds caught 55/58; past-escape seeds 16/20.
Calibration: backtested 2/2 (W0). Degradations: no Linux build image (docker CLI broken).
Scheduled, not open: 4 production/tenant/time checks, owners and dates in residual.jsonl.
Since signoff: 1 challenge (relabel of H-12); 0 escapes; 0 reopened rows.  Built 0/41 · Deployed – · Live – · Ceilings 3/3 measured.
No new critique was run to answer this. More search: cc-research extend --rounds 2 (expected +0.3 holes, about 1 day).
```

---

## 7. The re-ask protocol

1. **Detect from any cwd.** `hooks/research-precognition-nudge.sh` is already registered on UserPromptSubmit (read from `~/.claude/settings.json`), so no settings migration is needed. It gains a branch that:
   - matches the completeness-ask regex built from the 88 historical asks (`/tmp/rescomp/internal/reask_scan.py` patterns plus `100.00/100.00`);
   - resolves the program from `programs.json`: named in the prompt, the cwd's repo, or the single active program, otherwise a one-line status per active program;
   - injects `cc-research verdict --render --program <P>` as additionalContext with *"RELAY VERBATIM, then at most 3 lines. Do not start a critique, a fresh-eyes review, or a new panel."*
2. **Relay.** The answer's first lines are the rendered vector. The wrap-ledger rung stays a separate `V9` line. `/are-we-done` gains a `Goal:` line from the same render.
3. **Only deterministic checks run on an ask.** These are re-runs of `recheck_cmd`s whose TTL expired and the trunk diff on `depends_on_paths`. Live-environment harness rows are **not** re-executed per ask: the render cites their last scheduled run with a timestamp. A red live row is re-run n=3 and is reported as drift or flake unless it is red in 2 of 3. This closes the judges' "live flake flips a yes" flaw.
4. **Idempotent.** An identical ask re-renders the same words, marked "unchanged since HH:MM".
5. **Two verbs, no third.**
   - `cc-research challenge --locus … --names … --text …` enters typed intake (§8).
   - `cc-research extend --rounds m` states its price first (`extend_yield`, cost in days and quota). It then runs pre-registered additional rounds on the certified snapshot. Their looks are counted in the certificate (Lewis 2021 on sequential bias), and it is never a reopen.
6. **Symmetric enforcement.** A new `completion-assert.sh` arm applies while a certificate exists. A reply to a completeness ask:
   - may say "no" or "not yet" only if it cites a hole id verified M1 in-frame **this turn**, a CR id, or a failed G10 row;
   - may say "yes" only if it relays a verdict rendered **this turn**.

   Otherwise it blocks, with the reason *"regenerated audit: answer from cc-research verdict, or file cc-research challenge"*. The existing false-done arm extends to `cc-research gate` exiting non-zero.

---

## 8. Post-gate change control

`cc-research challenge` runs the typed intake. Build-time discoveries, rehearsal and sweep findings, and operator concerns all use it.

| Step | Rule | Outcome |
|---|---|---|
| 1 Locus | no specific locus or no id | GENERIC: logged, no work |
| 2 Dedup | matches a ledger, residual or backlog row | **relabel**: answer from that row. Re-raising needs evidence dated after the disposition |
| 3 Frame class | in-frame miss (C3–C8, C11, C2u) · frame defect (the FAC should have had it) · frame expansion (C2n, a new requirement) · contact residual (already an R row) · drift (a re-check changed) | decides who pays and what reopens |
| 4 Materiality | §3.5 vote plus reproduction | M2/M3 go to the build backlog, never a research reopen |
| 5 Impact | `cc-research impact H-x` walks `depends_on` / `affects` / `supports` / `load_bearing_for` | the smallest set of rows, CUs and build waves |
| 6 Scoped repair | fix by integration. Then a **delta round**: T = 4, ≥2 families, on the changed spans plus their dependents, with fresh fix-cohort seeds in those spans. **At most 2 delta rounds per escape**; a second non-dry delta marks the CU "open escape" and holds only its dependent waves | the certificate is amended as v(n+1), never replaced |
| 7 Accounting | every **escape** (an in-frame M1) is counted in V4 **against the forecast count printed at signoff**. There is no redefinition: the operator sees every escape as one. Separately, if escapes exceed n_pred95, that is a **calibration breach**: the stratum is re-certified from its registers up and the breach is recorded. A frame defect adds a FAC row. The escape mechanism joins the escape library, plus one line in `docs/lessons/` naming the lens that missed it | method metrics |
| — | frame expansion: `Scope (grown, cause=operator)`, a CR, a mini-frame with its own censuses, premises, contact and one round, priced before it starts. **Not a take-back** | |
| — | drift: a CR with `cause=reality_moved`; only the dependents are revalidated. **Not a take-back** | |

---

## 9. Timeline and budget model

### 9.1 Units
- **Agent-runs and panel-runs** at a fixed brief and effort. Execution effort, not calendar time, predicts reliability growth (Wood 1996).
- W0 measures wall time, tokens and **weekly-quota %** per run per family (`claude-accounts` before and after).
- Parallelism p ≈ 6–8: 4 accounts at `cc-wave-plan` ≤2 per account per wave, plus codex and gemini.
- `Wall(phase) = max(critical path, Σ unit cost / p) + dated operator waits`.

### 9.2 Priors for a medium greenfield
The example has about 15 D-rows, 12 axes in scope, 10 censuses, 60 premises and 40–70 A-rows. These are estimates to calibrate, not measurements.

| Phase | Runs | Wall p50 | Operator |
|---|---|---|---|
| P0 | ≈25 (incl. 12 frame-critique panel-runs) | 2 d | 60–90 min interview + 15 min signoff |
| P1 | ≈40 + ≈30 probes | 2 d | 0 |
| P2 | ≈40 (VOI order, timeboxed) | 3 d | class-C rulings, dated |
| P3 | ≈30 (harness, skeleton, faults) | 2.5 d | 0 (E6 references were given at P0) |
| P4 | ≈8 (incl. seed author + realism) | 0.5 d | 0 |
| P5 | 8 × rounds + ≈4/round adjudication, verification and votes: p50 7 rounds ≈ 84 runs | 3.5 d (≈0.5 d per round) | 0 |
| P6 | 12 rehearsal + ≤2 sweep + gate | 1 d | 15 min signoff |
| **Total** | **≈260–300 runs, ≈40–75M tokens** (150–250K per run) | **≈14.5 working days p50, ≈17 p90** | **≈2–4 h + dated rulings** |

**Anchors:**
- Research phases in the corpus converged in 1–2 days, and the weeks came afterwards as leakage: LIMIT_RECOVER_100P spent 22 days and 30 goals after "complete".
- DOCS_CONSOLIDATION took 25.75 h and was never reopened.
- sevenrooms was idle 33 of 35 days. **Every operator gate therefore carries a date**, and `cc-research forecast` prints dormancy as blocking days, not as research.

### 9.3 The finite guarantee
The ceiling is computed at ratification and printed on the contract page:
`Ceiling = 1.5 × Σ phase budgets + R_abs × round time + P6`. With the defaults that is 1.5 × 10 d + 10 × 0.5 d + 1 d = **21 working days**.

It can be exceeded only by an explicit operator act: a veto of an overrun default, or `extend`. Calibration shrinks the 1.5 factor as `research-calibration.jsonl` accumulates programs (reference-class forecasting).

### 9.4 The dial: where "100× effort for the last 1%" actually buys something
The operator picks one tier at P0 from priced rows. The "left" columns come from simulation, at N₀ = 60 material at first freeze and 5% invisible to every family. Round 1 and W0 replace them with measured values.

| Tier | Stop | Seeds | Rounds p50/p90 | Certification panel-runs | Desk-findable material left: mean, P(≥1) | Total left incl. desk-invisible | Source |
|---|---|---|---|---|---|---|---|
| decision | K=1, T=8 | 40 | 5 / 6 | ≈40 | 1.23, 0.71 | ≈4 | `tier_curve.out` |
| **build (default)** | K=2, T=8 | 60 | 7 / 8 | ≈56 | 0.76, 0.51 | 4.16 | `synth_stop.out` (fp 0.25) |
| max | K=3, T=8 | 100 | 9 / 9 | ≈72 | 0.50, 0.38 | 3.83 | `synth_stop.out` (fp 0.25) |
| max-wide | K=3, T=16 | 100 | — | ≈112 | 0.23, 0.20 | ≈4 | `width_vs_depth.out` |
| literal 1% | K=4, T=16, **300 seeds all caught** (rule of three) | 300 | — | ≈128+ | 0.16, 0.14 | ≈4 | `width_vs_depth.out`, `stopping_model.out` §1b |

**The finding the operator needs to see.** Beyond the build tier, more desk rounds shrink a residual that is already below one hole. The ≈4 holes that no desk reviewer finds do not move at any tier. In the corpus, that mass is C9 contact (30 holes, 24 probe-able locally) plus unforeseeable drift.

**So the operator's surplus budget goes, in order:**
1. **P3 contact depth**: more environments, production-scale rigs, an E6 prototype in front of the operator;
2. **the P0 frame critique**: more families and rounds on the small frame;
3. **then the max tier.**

`cc-research extend` quotes `extend_yield` for exactly this reason.

---

## 10. The honest residual

These are what no upfront method can eliminate, and what the protocol does about each.

| Residual | Why it cannot be zero | What the protocol does |
|---|---|---|
| **Holes every model family misses** | Not identifiable from overlap (Link 2003). In the model, ≈4 remain at every tier | contact before the claim (P1, P3); seeds whose difficulty includes the invisible share, so μ̂ **states** it (`synth_stop.out`: μ̂ 4.49 vs true 4.16); budgeted post-build verification. The certificate says so in words |
| **Production, external tenant, elapsed time, operator's eye** | the property lives only there (6 of 200 historically: holes 16, 34, 95, 121, 134, 170) | residual rows with owner, date, verify command and falsifier (G11); a post-build verification wave; a failure reopens only its dependents |
| **Genuinely new requirements** | the operator's intent changes (6/200 = 3%) | CR `cause=operator`, a mini-frame and a price; **not a take-back** |
| **Unforeseeable drift** | the world moves (4/200) | TTLs, recheck commands and sha stamps; scoped revalidation; **not a take-back** |
| **Estimator calibration** | family correlation on design review and seed realism are unmeasured; the sims assume them | **W0 backtest blocks everything.** Certificates print "uncalibrated" until W0 and then the backtest record. The family co-detection matrix is recorded per program. A calibration breach re-certifies the stratum |
| **Materiality mistakes** | M1 vs M2 is a judgment (the TM2 case moved 13↔5 by definition) | 3 mixed-family votes plus reproduction; M2-disputed is audited against build evidence; mistakes are counted |
| **Frame defects** | a pattern no FAC row and no critic anticipated | counted as `frame_defect`; the FAC grows by one row per defect, so each program is less exposed than the last |
| **The method's own machinery** | new code can itself hold C7-type holes | every gate and estimator has a planted-input test that must go red; the first program is an explicit calibration run |
| **Expected escapes > 0** | follows from all of the above; at the build tier P(≥1 desk-findable material hole left) ≈ 0.5 in the model | the forecast count is printed **at signoff**, so an escape is a forecast event, shown and counted, never a silent reversal. Blindness toward codex and gemini is detection-only (same UID) |

---

## 11. Build list for this environment

Execution locus is **S** (a dispatched session per wave, in its own worktree, landed via the project `/ship`), except W0a.

| Wave | Deliverable | Exit criterion (printed by the session) |
|---|---|---|
| **W0a** (L, hours; urgent, /tmp is reaped) | Persist `/tmp/rescomp/**` (taxonomy, ledger, forensics, internal and external research, designs, sims, this synthesis) to `docs/research/research-completeness-2026-09-30/`. Derive `escape-library/escapes.jsonl` from `taxonomy_holes.py` (129 desk-findable rows with receipts) and `frame-axis-checklist.jsonl` from §3.4 | `git ls-tree origin/main -- docs/research/research-completeness-2026-09-30/` lists them |
| **W0** (S, blocking; the positive control for the whole method) | Run P4–P6 by hand (scripts plus a Workflow) on historical snapshots with known later holes: the VoiceInk latency plan at `989f6dbf` 2026-09-28T05:21:27Z ("It's now done"; 20 defects and the upstream axis came after) and the quota plan at `ba08cab8` 19:25Z (D22–D24 came after). **Measure:** recall of the known later holes before "done"; the family co-detection matrix; seed realism; seed distraction (seeded vs unseeded copy); quota % per panel-run per family; **`--setting-sources local` stripping on the Opus-5.5-capable binary**; `dontAsk` refusing out-of-cwd reads; gemini auth under a real call; whether pi or ollama is usable as a fifth family; how headless Fable runs meet `frontier-spawn-gate`. Then file AD1–AD3 as one class-C packet carrying the **measured** price table | a report at `docs/research/cur-w0-backtest.md` with each measurement and the receipt that produced it |
| **W1** (S) | `bin/cc-research` (Python). Verbs: `init` (scaffold, topic lock, `programs.json`), `index`, `frame {new,lint,render}`, `census {add,verify}`, `premise {add,due}`, **`probe run`** (records env, stdin, n and raw output; refuses `mutates_live` without `--sandbox`; computes tiers), `probe-kit {doctor,install}`, `harness selftest`, `trace check`, `reconcile`, `lint`, `freeze`, `impact`, `hole add\|challenge`, `cr`, `estimate`, `forecast`, **`gate`**, **`verdict --render\|--machine`**, `extend`, `budget`. Append-only stores with folds, the same model as `cc-backlog` | its bats and pytest suites green; **every gate row and estimator goes red on a planted input**; the estimators reproduce `stopping_model.out` §1d (47 → Chao2 56.0; +3.1/7.6/18 panels) and `synth_stop.py` on fixture matrices |
| **W2** (S) | Panel machinery: `cc-research panel run` (couriers for `claude -p --setting-sources local --allowedTools "Read Grep Glob" --permission-mode dontAsk`, `codex exec -s read-only`, `gemini -p --approval-mode plan`; Fable cap accounting); sanitized-bundle builder (`git archive` with stripping); encrypted vault (`openssl` plus a keychain key); `seed {author,apply,match,realism}` with quote-anchored patches and orphan censoring; the `cur-round`, `cur-contact`, `cur-frame-critique` and `cur-rehearsal` Workflows under `~/.claude/workflows/`. Agents write to disk and return paths and hashes, since the orchestrator has no filesystem; **the snapshot sha and bundle hash go in every prompt** | one live round on a toy program: 8 complete panels across 3 families, integrity grep 0 hits, a seeded defect caught and matched, and an orphan censored |
| **W3** (S) | Hook and command edits. `hooks/research-precognition-nudge.sh`: the re-ask branch (§7.1; no settings migration). `hooks/completion-assert.sh`: the symmetric arm. `scripts/wrap-ledger.sh`: a `GOAL` field from `verdict --machine`, and absent DoD → "unknown" at `:2286-2288`. `hooks/dod-persist.sh`: the superlative lint and `cause=` on `Scope (grown)`. `commands/are-we-done.md`: the `Goal:` line. `scripts/handoff-fire.sh`: `--requires-gate <P>`. `bin/cc-signoff`: a `research:<P>` mode reusing arms 1–3 without a mission row | bats: a completeness prompt from a **different cwd** injects the certificate; "No, one more check" without a hole id is blocked; "yes" without a render from this turn is blocked; an absent DoD reads unknown; `handoff-fire --requires-gate` refuses on NOT CERTIFIED; cc-signoff refuses from an agent ancestry |
| **W4** (S) | The quota removals and methodology. The zero-allowed form replaces `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37-38` and `skills/research-subagents/SKILL.md:798,823`. The negative-space trigger is scoped to P0 frame critique. `SKILL.md:944-948` "apply more aggressively" routes to `challenge` when a program exists. OASIS criterion 3 (`c·N^α`, no asymptote) is pointed to `cc-research estimate`. New skill `research-program` and command `/research-program`: the P0 script, 12 questions, FAC, materiality rubric, and the panel, seed-author, adjudicator, verifier and rehearsal briefs | the skill passes its own frame lint; a replayed `/research` wave returns a valid "zero findings" without being coerced |
| **W4-op** (operator) | Rule AD1–AD3 (one class-C packet from W0). On adoption: a one-sentence F1 edit in `CLAUDE.global.md` (and the live `~/.claude/CLAUDE.md`) and the D4 carve-out, each carrying `Replaces: … — ruling pending` until ruled | the packet is actioned by the operator |
| **W5** (S; the next greenfield) | The full P0–P7 program. Post-gate escapes are tracked for 30 days after build start. `research-calibration.jsonl` is updated with actuals, the family matrix and escapes against forecast | CERTIFIED issued; the 30-day escape report written |

**Tooling limits today**, each re-verified by `probe-kit doctor` at P1 and degraded explicitly, never silently:
- the docker CLI panics, so there is no Linux-image probe;
- Java/TLC and `hypothesis` are absent, so small-scope enumeration scripts are used instead;
- `grok-wiki agents` fails with EACCES (`skills/grok-wiki-audit/SKILL.md:3,16`), so couriers call the vendor CLIs directly;
- gemini auth is unexercised.

---

## 12. How each judge's fatal flaw is closed

| Flaw (judge) | Closed by |
|---|---|
| Seeds planted only at the end overstate recall; bound coverage 0.56–0.78 (FCR, RCF) | carried original cohort from S₁ plus carried fix cohorts in edited spans (§4.6.4); `synth_stop.out` coverage 1.000 with realistic seeds |
| FCR default-proceed contradicts "build blocked while red" | one CERTIFIED verdict with carried rows that block only their dependent waves; overrun `expired-actioned` converts open rows to carried rows (§6) |
| FCR G8 thresholds near-unreachable; singletons suppressed | no residual-threshold gate at all: stop = dry-K or cap; estimates are **stated**, and the cap costs no measured residual (`synth_stop_split.out`) |
| SS Q2 unreachable with realistic seeds; tie→MATERIAL; κ gate; uncapped Q4/Q6; timebox restarts | μ̂ stated, not gated; ties → M2-disputed; agreement reported with one re-adjudication; hard-tail detector gets one attempt then a named weak lens; realism gets one rewrite; divergence spends rounds from the same R_max |
| SS redefines "take-back" so escapes inside the bound are invisible | every escape is counted in V4 against the forecast printed at signoff; calibration breach is a separate, additional signal (§8 step 7) |
| SS carried-seed mechanics across edits unspecified | quote-anchored seed patches re-applied per snapshot by script; orphans censored; the lead never sees seeds (§4.6.4) |
| RCF termination waits on the operator (class C, no default); uncapped P2/P4→P3 loops | class-B default-proceed on overrun; class C only for escalation surfaces and operator values, and those become carried rows, not blockers; the three allowed loops are all capped (§2) |
| RCF G9 needs Chao2 residual <1 from a single full round | certification runs full rounds until dry-K or a forecast-based cap; delta rounds exist only after the gate |
| RCF re-executing live harness per ask lets flake flip a yes; rehearsal uses flip-inducing wording | per-ask checks are deterministic only, and live rows cite scheduled runs with n=3 flake handling (§7.3); rehearsal uses frames as lenses, not challenge wording, and runs once (§4.7) |
| Contamination of Anthropic panels by resident instructions and auto-memory; escape seeds matching resident lessons | panels are headless `claude -p --setting-sources local` in a sanitized, history-free bundle at a new path (probe-verified strip, this session); escape recall per family flags leakage |
| Same-UID vault readable; blindness only detected afterwards | seeds encrypted at rest; `dontAsk` plus read-only tools for Anthropic panels; integrity grep voids panels; the remaining codex/gemini exposure is stated in §10 |
| Phase goals with operator-only conjuncts never clear | goals end at "gate printed its verdict with every row PASS or FILED" (§2) |
| "Red on a planted defect" undefined for greenfield | known-bad/known-good fixtures plus the contact skeleton (§4.4) |
| Calibration never checked before shipping (FCR, RCF) | W0 backtest blocks all later waves; certificates print "uncalibrated" until it reports |
| cwd-keyed re-ask hook misses asks from other panes | `programs.json` registry; the hook resolves the program from any cwd (§7.1) |
| F1/D4 changes not flagged as operator practice (SS, RCF) | AD1–AD3 with convictions, one class-C packet, `Replaces: … — ruling pending` (§1) |
| Fable spawns in Workflows may bypass `frontier-spawn-gate` | program-level Fable cap enforced by `cc-research panel run`, headroom checked first; the gate interaction is a W0 check |
| Ratification forgeable through cc-decide `action` (no agent guard, verified) | ratification and final signoff through `cc-signoff research:<P>` (operator-only ancestry, content pin, forgery advertised) |

---

## 13. Receipts index

- **Taxonomy and ledger:** `/tmp/rescomp/taxonomy.md`, `taxonomy_holes.py`, `python3 /tmp/rescomp/taxonomy_stats.py`. Re-ask corpus: `/tmp/rescomp/loop_asks.json` (88 asks).
- **Designs:** `/tmp/rescomp/design/frame-contract.md`, `statistical-stopping.md`, `reality-contact.md`. Designer sims: `stopping_model.out`, `cert_calibration.out`, `carried_seeds*.out`, `tier_curve.out`, `width_vs_depth.out`.
- **This synthesis:** `synth_stop.py/.out`, `synth_stop_split.py/.out`.
- **Anchors verified this session:**
  - `scripts/wrap-ledger.sh:616-623` (REMAINDER counts `- [ ]`) and `:2286-2288` (absent DoD → ✅ rung);
  - the goal lesson `docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md` (exists);
  - `hooks/frontier-spawn-gate.sh:2,9,90` (Agent + Bash matchers);
  - `~/.claude/model-config.yaml:1116` (`max_fable_spawns_per_session: 6`);
  - `bin/cc-decide:22-44,182-186` (class B requires `--default` and `--deadline`; class C never defaults; `expire-sweep` → `expired-actioned`; no agent guard on `action`);
  - `bin/cc-signoff:1-30,74` (operator-only, content pin, `cc-signoff <row-id> --evidence`);
  - `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37-38`, `skills/research-subagents/SKILL.md:353,798,823` (quotas);
  - `hooks/completion-assert.sh:1278` (D4 "the answer is always yes");
  - `CLAUDE.global.md:617` (F1);
  - `commands/are-we-done.md:70-72` ("exhaustively");
  - `skills/ground-up/SKILL.md:14-18` (superlative ban);
  - `~/.claude/settings.json` UserPromptSubmit already registers `research-precognition-nudge.sh`;
  - `~/.claude/workflows/` holds `pyramid-fans.mjs` and `freewin-probe-t1-t2.mjs`.
- **Contact probes this session:** the `claude-latest -p` pair (default vs `--setting-sources local`: quoted vs `NONE`) on 2.1.114; `claude-latest --help` (`--bare` needs an API key; `--setting-sources` exists); `codex login status` => logged in; `command -v gemini pi ollama` => present.
- **External:** `/tmp/rescomp/external/{stopping-rules,unseen-estimation,llm-failure-modes}.md` with their primary citations (Callaghan & Müller-Hansen 2020; Chao et al. 2009; Briand et al. 2000; Link 2003; Dalal & Mallows 1988; Hanley & Lippman-Hand 1983; Huang et al. 2024; FlipFlop; FixedBench; Kim et al. 2025; Böhme et al. 2021; Deng et al. 2024; Wood 1996; Lewis et al. 2021).
