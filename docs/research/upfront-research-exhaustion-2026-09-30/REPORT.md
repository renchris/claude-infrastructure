# Upfront research that ends: a no-take-backs method for "100.00/100.00 complete"

Date: 2026-09-30. Scope: greenfield research and planning run through Claude Code on this machine.
Status: **method version 1.1, frozen; not certified.** After landing, the report was put through its own stopping
rule twice, and neither pass reached the "3 quiet rounds" exit. Desk review of this document stops here, at the cap of
2 change rounds the method itself sets. Section 10 records both passes and the 17 open items, which are acceptance
requirements for the build. Later changes come only from building, testing and the pilot, applied as priced edits to
named sections, never as a rewrite (§9, decision 8).

Receipts point into `evidence/` beside this file unless they start with `~` or a repository path. Repository paths are
relative to `~/Development/claude-infrastructure` at trunk `8a2a9acda`. Every simulated number comes from a stdlib Python
model you can re-run (Appendix C) and is **uncalibrated** until the calibration run measures its inputs.

---

## 1. The answer

No upfront method can certify literally zero unknowns. That would require examining at least 95% of every place a hole
could be (`evidence/external/stopping-rules.md:75`), and holes that every AI reviewer misses stay invisible to any amount
of reading (`evidence/external/unseen-estimation.md:26`). But that limit is not what you are running into. Of 200 holes
that surfaced after a "complete" claim, 129 (64.5%) were findable by desk research and only 10 (5%) were unreachable by
any upfront process on this machine (`evidence/taxonomy.md:9-18, 277`). They surfaced late for four fixable reasons:
the checks ran after the claim instead of before it; "complete" was measured against no written list; your standing
rules and research prompts require a new item on every ask; and new ideas re-enter as scope with no parking place. The
method below fixes those causes. You sign a list of testable frame rows (a "frame") before research starts, including
what "complete" means. The research makes contact with the real environment before any design decision, runs a fixed,
pre-registered number of blind review rounds across three model vendors on a frozen plan, and issues a certificate:
"100.00% of the signed frame is closed", plus a printed forecast of how many material changes to expect after signoff
and the most it could be at 95%. After that, asking "are we 100.00/100.00 complete?" relays the stored certificate. A
tool-level block keeps research tools off unless the prompt is positively labeled as work, and the gate measures how
often a re-ask is misread. A reply that adds an item the certificate does not carry is blocked, whether it opens "yes"
or "no". New ideas park in the next version, and every later change is
counted against the printed forecast instead of reopening research. In the model, the 95% upper bound of that forecast is exceeded (a
take-back) in about 1–4% of programs (`evidence/final/profile_sim.out:6-27`). The typical-case forecast itself is
exceeded more often; the simulation does not yet report that rate. Most programs should still expect at least one material change after signoff (about 6–9 in 10 with a
strong front end). The only things that shrink that number are a better front end and earlier contact with reality;
more reviewers barely move it. The method needs two rulings from you, made in the intake sitting before any program
starts: accept this definition of complete, and exempt active programs from the parts of your standing rules that
currently force "no, one more thing".

**Updated 2026-10-04 (v1.2), from measured inputs.** The two figures above, "about 1–4%" and "about 6–9 in 10", are
the model at assumed inputs. At the inputs the calibration measured over 16 plans
(`docs/research/research-calibration/REPORT.md` §3, §5; `evidence/params-measured.json`):
- The 95% bound is exceeded in at most 2.2% of simulated programs, and held on 15 of 16 replayed plans.
- The typical-case forecast is exceeded in 22–38% of simulated programs at the assumed inputs, and was on 6 of 16
  replayed plans.
- **Every program should expect material changes after signoff: the chance of at least one is 1.00 in every profile**,
  not 6–9 in 10. A Lite or Standard program is left with about 9 changes after signoff on the reading closest to the
  operator's (a call is false only when history proved it false; modeled,
  `docs/research/triage-precision-study-2026-10-04/REPORT.md` §1).
- More reviewers do not shrink that number. At measured inputs they raise it (§3.12 update, §6.1).
`scripts/research-kit/estimate.py` and the contract page now print these measured figures by default; the assumed
set is kept as a labeled contrast (`--base`).

---

## 2. Diagnosis: why holes keep appearing

### 2.1 What was measured

Eight forensic passes read the 88 completeness re-asks in your transcripts (rebuilt by `~/.cache/rescomp-rebuild/extract.py`; the raw prompts are kept out of this public repo) and extracted
every hole that surfaced after a prior "complete / good to close / 100%" claim: **200 holes**, one row each with a
receipt (`evidence/taxonomy_holes.py`; counts re-derived by `python3 evidence/taxonomy_stats.py`). Four audits read the
machinery that asserts "complete" (`evidence/internal/`). Five literature reviews covered stopping rules, estimating
unseen defects, LLM failure modes, high-assurance systems engineering, and the limits of desk research
(`evidence/external/`).

| Why the hole survived to the "complete" claim (the evidence file's class code) | Holes | Decision-changing | Findable by desk research |
|---|---|---|---|
| A population was never enumerated: an option (including "use what exists"), caller, instance, platform, account, concurrent actor, publication surface (C4) | 32 | 22 | 29 |
| Contact-only: the property lives in the real environment and was certified on a stand-in (C9) | 30 | 13 | 1 (plus 23 more probe-able on this machine) |
| A load-bearing premise was asserted without a primary check (C3) | 29 | 12 | 26 |
| The check behind "done" could not fail on the defect (C5) | 29 | 8 | 13 (15 more only at build) |
| The claim's frame was narrower than the question; the item was already known (C1) | 23 | 13 | 23 |
| Operator intent arrived after the claim: 6 genuinely new, 6 never asked for (C2) | 12 | 2 | 2 |
| Research existed but never reached the plan (C6) | 12 | 7 | 12 |
| The session's own edits created the hole (C7) | 10 | 3 | 8 |
| Adversarial review ran late or stopped early (C8) | 8 | 5 | 8 |
| The world moved during or after the research (C10) | 8 | 4 | 3 |
| "Done" had no falsifiable test, such as a superlative with no number (C11) | 7 | 6 | 4 |
| **Total** | **200** | **95** | **129** |

Receipt: `evidence/taxonomy.md:24-37`. About half the holes (95) were decision-changing, 42.5% were refinements and 3.5%
were cosmetic, so the loop is not mostly noise (`:253-263`). Materiality and class were single-pass judgments by one
rater per shard, and "desk-findable" is hindsight-assisted, especially for unenumerated populations (`:338-343`).

### 2.2 The root causes, with counts

1. **The checks ran after the claim.** 120 of 200 holes (60%) were misses inside a frame the research already had, and
   70 of the 95 decision-changing holes were desk-findable (`evidence/taxonomy.md:263, 274`). The ask was usually the
   first adversarial audit: "The check did not exist until the question was asked" (`evidence/internal/close-assertion.md:151-155`).
2. **"Complete" was measured against nothing written down.** The Definition of Done (DoD) line carries the superlative
   verbatim. The ledger's "remainder" counts `- [ ]` checkboxes, which only 4 of 76 DoD files contain. A missing DoD
   still renders ✅ (`evidence/internal/close-assertion.md:45-65`; `scripts/wrap-ledger.sh:2286-2288`). So 23 holes
   (11.5%) were items already known and recorded, re-rendered as "new" because the next question used a wider frame
   (`evidence/taxonomy.md:14`). "100th percentile / perfection" appears in 80 of 88 asks and maps to no testable
   criterion (`evidence/design/SYNTHESIS.md:207-208`).
3. **Your prompts and standing rules require a new item on every ask.** Three research prompts have quotas: "Find 2-3
   gaps" (`agents/deep-research.md:187`), "name 1-3 plausible axes … MISSING" (`agents/research-decomposition-critic.md:37`),
   "List 3 with reasons" (`skills/research-subagents/SKILL.md:353, 798, 823`). The Follow-On Gate passes any refinement
   under "nothing left on the table" (`CLAUDE.global.md:617`). The Stop hook's "offer instead of drive" check says "the
   answer is always yes … DRIVEN (you do it now)" (`hooks/completion-assert.sh:1284`). No materiality definition exists
   anywhere (`evidence/internal/close-assertion.md:89-105`). Measured on 280 genuine completeness asks, 268 (95.7%)
   triggered tool calls before the answer (5,688 calls, about 20 per ask) and 44 (15.7%) launched a subagent or
   Workflow inside the same turn. Of the 73 replies that opened "yes", 20 (27%) also named a new item
   (`evidence/adversary/llm/ask_turns.out:2-8`).
4. **Open-ended critique loops generate holes; bounded passes converge.** The session's own edits created 10 holes (5%)
   (`evidence/taxonomy.md:285`). Critic loops that fix inside the loop did not converge: 23, 21, 24, then 28 new
   blockers per round, none repeated, and 37→26→22→17→14→22→…→16 over 13+ rounds. Bounded passes over a fixed artifact
   did converge: 10→7→2 and 7→1→0 (`evidence/taxonomy.md:17-18, 296-299`).
5. **Contact-only and moving-world holes were treated as research failures.** 30 holes (15%) lived only in the real
   environment, and 24 of those could have been probed on this machine during research (run it under launchd, run the
   handed command, query the live process). Only 10 (5%) needed production, a real tenant, elapsed time, or were
   unforeseeable drift (`evidence/taxonomy.md:15, 277`).
6. **Intent and new ideas arrive late and re-enter as scope.** 12 holes (6%) needed information only you held; 6 of
   those existed and were never asked for (`evidence/taxonomy.md:27`). In the 61 loop sessions, 94 of 532 genuine
   prompts (17.7%) introduced a new idea: a median of 1.6 per active session-day, with bursts of 7 in one session
   (`evidence/adversary/opscope/adv_opscope_idearate.py`, re-run this session). New question frames keep being coined:
   "no take-backs" first appeared 2026-09-16, "end-game" 09-17, "left on the table" 09-30
   (`evidence/adversary/llm/frame_birth.out`).

### 2.3 Five examples from your transcripts

Each quote below was re-read from the raw transcript this session (`evidence/final/verify_quotes*.py`).

1. **Session state reported as job state.**
   `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-143333-63422/7f533f05-91fa-42d0-89ef-cd7976c423d5.jsonl`.
   At 2026-09-20T09:04:52Z the close read "✅ Complete & live on trunk". At 09:07:21Z you asked "Are we 100.00/100.00
   correct and complete … deployed and live now?" At 09:08:24Z the answer was: *"No. … 0 of 7 waves are built. 'Safe to
   close' described my session's state, not the job — and the job is not done."*
2. **Repeated asking, each answer reopened.**
   `~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/ba08cab8-7b28-438a-a981-61c101a5c080.jsonl`.
   At 2026-09-14T19:25:38Z you asked "Do you deem it 100.00/100.00 complete … If so, I approve". At 19:25:52Z: *"Pass one
   produced ten findings. Pass two corrected two of them and added seven. That is not the shape of a converging
   process."* At 19:28:54Z: *"New findings per pass: 10 → 7 → 2."* At 21:26:48Z you asked the same question again, and
   the plan had gained two more defects.
3. **The check was invented by the question.**
   `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/989f6dbf-0216-45d0-a061-f998c29ab27c.jsonl`.
   At 2026-09-27T23:56:55Z you wrote: *"We don't fire off implementation until we are fully end-game complete -- no
   take-backs, redo, or incremental research later down the line."* At 2026-09-28T05:26:16Z: *"No, not yet. One check
   remains … plan v2 was assembled by script from about 40 changes, and nobody has re-read the finished document end to
   end."* That fresh read then found 20 defects (`evidence/taxonomy.md:154`).
4. **Asking caused the re-read.**
   `~/.claude-next/projects/-Users-chrisren-Development-reso-web-app/5245ce63-eb3a-4037-91e2-a8e38b3bf6d8.jsonl`
   @2026-08-27T20:26:24Z: *"✅ Complete & live — but your question caught something … Good to close: yes … Correcting my
   earlier '100%' though: the task is complete, hazard H15 is not. … Asking made me re-read my own work instead of
   recalling it, and two things were wrong."*
5. **An open critique loop that never converged.**
   `~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/7c395da7-fbbe-4123-8bd5-2456787d12c3.jsonl`
   @2026-09-29T15:58:52Z: *"each round's critics found 23, 21, 24, then 28 new blockers and majors, none of them repeats.
   Each fix adds more machinery of its own … and the next round critiques that."*

Your own stated rule, which the method must reconcile with its definition (§3.1):
`~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/61853387-c813-4727-83f9-2139b1e2b36d.jsonl`
@2026-09-14T05:05:20Z: *"ALWAYS fix until 100.00/100.00 … including all new found work, follow-ons, loose-ends. Do we
need to modify our CLAUDE.md or stop hook?"*

### 2.4 What the evidence rules out

- **Certifying zero unknowns.** With 60 holes already found, stating "at most a 5% chance any desk-detectable hole
  remains" at 95% confidence needs 3,654 planted test defects, every one caught (`evidence/design/stopping_model.out:12`).
- **Buying certainty with more reviewers.** Holes every reviewer family shares cannot be estimated from overlap at all
  (Link 2003, `evidence/external/unseen-estimation.md:110`). More reviewers shrink only the desk-detectable part (§3.12).
- **Letting a model re-judge "complete" on each ask.** A neutral review of a correct artifact flags something at least
  88% of the time, and "Are you sure?" flips answers 46% of the time (`evidence/external/llm-failure-modes.md:11, 35, 46`).
  Asked repeatedly, an unanchored question will keep producing items whether or not the plan has holes.
- **Research phases were not the long pole.** In seven greenfield cases, research took hours to about 2 days and
  converged. The weeks came afterwards: contact defects, axes never written down, late intent, drift, and dormant
  operator gates (`evidence/internal/greenfield-cases.md:17-23, 138-145`). The plan that closed and stayed closed ran
  all 58 acceptance commands before building, found 45 unsound, fixed them, and finished in 25.75 hours without a reopen
  (`evidence/internal/plan-lifecycle.md:13`).

---

## 3. The method: one protocol, eight stages

**Words used below.**
- A **program** is one greenfield research effort run under this method.
- The **frame** is the list of what research must settle: decisions, testable acceptance checks, the populations
  that must be enumerated, premises, sources, and contact cells. You sign it.
- A **reviewer** is one AI model process that reads the frozen plan blind. A **round** is one set of reviewers run in
  parallel.
- A **seed** is a defect planted on purpose and hidden from everyone but a sealed script. It measures how much the
  reviewers catch.
- A **material** finding is one that meets the rubric in §3.11. Everything else is a refinement (done at build),
  cosmetic, or rejected.
- **Desk-detectable** holes are ones at least one reviewer could find by reading. **Invisible** holes are ones every
  reviewer family misses; only contact with reality finds them.
- **Decision packets** are your existing `cc-decide` records. Class B has a default that fires at a deadline; class C
  waits for you.
- `cc-research` is the new command-line tool this report proposes to hold the program's records and compute its gate
  (§8). Until it exists, a hand-run kit of seven scripts does the same job (§8, item 7).

### 3.1 Preconditions, settled in the intake sitting before anything else

The program does not start until both rulings are recorded. If you decline either one, the program makes no
no-take-backs claim, and you can run ordinary research as today.

1. **The definition of complete.** "Research 100.00/100.00" means all of the following, on one frozen snapshot:
   - every row of the frame you signed is closed with a receipt a script checks. This part is exactly 100.00%;
   - review stopped under the pre-registered rule;
   - the certificate prints the forecast of material changes after signoff: the desk-detectable part, the invisible
     part, and their total, each with a 95% bound;
   - every item research cannot reach is listed with an owner, a date and a check;
   - you signed the content hash.

   You are shown your own words from 09-14 ("ALWAYS fix until 100.00 … including all new found work") and 09-27 ("no
   take-backs, redo, or incremental research later down the line"). You then record whether this definition supersedes
   them inside program scope. The contract page (§3.2, step 8) lists the **only** activities that happen after the
   certificate, and you sign that they are not research: narrowing a carried set on its dated probe, scheduled
   residual checks, scheduled freshness and market checks, fixing a counted escape, one bounded frame-delta cycle for
   frame omissions found during certification (§5.4), and the parked-ideas batch.
2. **The standing-rule exemption for active programs.** In any session whose DoD names an active program, from intake
   through build:
   - a refinement is filed to the program's apply-at-build list, not driven now. This replaces the Follow-On Gate's
     "nothing left on the table" test (`CLAUDE.global.md:617`; slim variant `CLAUDE.global.slim.md:248`) inside
     program scope;
   - a decision closed by its timebox, by a packet default or as a carried set carries a "research exhausted at
     timebox" receipt. That receipt satisfies the rule that research below 90% conviction is mandatory
     (`CLAUDE.global.md:619`, restated at `:464-465`; slim variant `CLAUDE.global.slim.md:249`). Further research on that
     row goes only through a priced, operator-bought extension or the row's scheduled narrowing probe;
   - a completeness or pushback question about the program is answered by relaying the certificate. Residuals the
     certificate names are not open work. This covers the read-only-turn rule (`CLAUDE.global.md:655`; slim
     `CLAUDE.global.slim.md:272`), the slim variant's close-question rule (`CLAUDE.global.slim.md:259`), the rule that
     offering remaining work is a defect (`CLAUDE.global.md:969`; slim `CLAUDE.global.slim.md:364`), and the Stop
     hook's "offer instead of drive" check (`hooks/completion-assert.sh:1284`). Both variants and their live copies carry
     the exemption: `~/.claude/CLAUDE.md`, and `~/.claude/CLAUDE.slim.md`, which the four account config directories
     (`~/.claude-next`, `-secondary`, `-tertiary`, `-quaternary`) link to as their `CLAUDE.md`;
   - new ideas park in the next version (§5.1).

   Outside active programs nothing changes. The exemption is keyed on a marker in the program's DoD line, which those
   rules and the hook read.

### 3.2 Stage 1: intake and the signed frame (lead session with you; 0.5–2 days by size)

1. **Mine before asking.** A read-only fan-out writes `intake-mined.md`, with every claim quoted and receipted. It
   reads prior research through the research index `docs/research/INDEX.jsonl` (topic, path, date, status), which the
   kit's `research-index.py` writes first (§8, item 7), because none exists today for the 406 research entries
   (`evidence/design/SYNTHESIS.md:42`). It also reads plans here and in sibling
   repos, memory (`cc-memory-search`), transcripts including subagent files, your messages (`msg`) for every named
   counterparty, prior rulings (`cc-decide list --all`), the backlog and mission board, and house rules that act as
   acceptance criteria. An owner for the topic must show a positive sign of life (a recent commit, a live pane, open
   custody) before a second plan may start. Three parallel plans for one topic happened once
   (`evidence/taxonomy.md:139`).
2. **Interview: one sitting, 12 questions, each pre-filled from the mining; you confirm or correct.**
   1. Who uses the deliverable on day one, and how is it installed: agent, human, or CI?
   2. Where does it run, what keeps it alive, what expires, and who re-authenticates?
   3. What binds it: prior decisions, private facts, relationships, accounts, tenants?
   4. What does "not lacking" mean? Give 3–5 positive references per taste axis, and name the judge.
   5. What is out of scope, in your words?
   6. What is irreversible or spends money, and what must never regress?
   7. What can move under us (upstreams, vendors, registries), and where could this be published or mirrored?
   8. What can only be verified in production or over time, and who owns that check?
   9. What is the deadline, and what happens if it is missed?
   10. How many research days is one decision-changing hole found after build worth avoiding? **The answer must be a
       number.** "Infinite" means never deploy, so the program does not start.
   11. Which profile (§6.1), shown with its price, forecast and calendar ceiling?
   12. Which of your historical question frames ("deployed and live", "nothing can beat it", "no loose ends") matter
       here? Each maps to a line of the certificate or is excluded in your words.
3. **Turn every superlative into numbers.** "Maximal", "best" or "100th percentile" becomes one or more acceptance
   rows. Each row has a numeric threshold, a ceiling measured first (in Stage 3), a branch for a negative result, and
   for taste a positive reference set with your eye as a dated gate. A ban-list is never acceptance. Anything drawn
   from an outside population is worded "best available as of <date>, ceiling measured <date>", so a later release is
   a next-version candidate, not a miss. A lint rejects any predicate matching
   `perfect|100th|maximal|best|exhaustive|absolute|flawless` without a number. Your words are kept verbatim as intent
   and are never the test.
4. **Fill the frame.** It holds decisions (each with options that must include "do nothing" and "use what exists",
   premises, what would flip it, how it will be closed, reversibility, timebox), acceptance rows, premises, populations
   to enumerate, sources (including ones we do not write: upstream trackers, registries, vendor rules pages, access
   logs, the public web, your tenants), contact cells, residuals, and certification units of at most 1,500 lines, plus
   one unit for each seam with a sibling plan. Keep 7–10 decision groups at the top level so omissions stay visible.
5. **Map the frame-axis checklist.** Every row below maps to a frame row or is marked not-applicable with a reason. Each
   row traces to at least one past hole (`evidence/design/SYNTHESIS.md:238-271`). Every future frame defect adds a row.

   | # | The frame must carry |
   |---|---|
   | 1 | Options include "do nothing" and "use what exists" |
   | 2 | Candidates enumerated from the artifact itself (repo, fork, installed), never from memory |
   | 3 | Upstream or base version as an explicit decision; the upstream tracker as a source |
   | 4 | Every checkout, copy and deployed instance |
   | 5 | Every caller and consumer, found by name, not by path |
   | 6 | Execution contexts: deployment interpreter, scheduler, CI or build OS, real device versus simulator |
   | 7 | Where it runs, what keeps it alive, what expires, who re-authenticates |
   | 8 | Concurrency and the fleet case: concurrent actors, more than one instance, generator-versus-UI races |
   | 9 | Publication surfaces: mirrors, forks, jobs that push |
   | 10 | Operator-owned accounts, tenants and devices |
   | 11 | Evidence beyond our own stores: access logs, trackers, the public web |
   | 12 | Prior invariants, each with a guard test |
   | 13 | Handed commands, run by the agent under the real invocation (no terminal, launchd) |
   | 14 | Platform and feature-support matrix |
   | 15 | Deliverable consumer and install path; house rules that act as acceptance |
   | 16 | Operator-private relationships and agreements |
   | 17 | Hazards: write paths to live data, destructive tools, irreversibility |
   | 18 | Seams with sibling plans: an owner for every producer and consumer |
   | 19 | A measured ceiling for every performance or superlative target |
   | 20 | A positive reference set for taste |
   | 21 | Pre-registered thresholds and a branch for a negative result |
   | 22 | Every hold carries an expiry |
   | 23 | Freshness: sibling trunk activity, registry releases, credential validity |
   | 24 | Research probes never change the live subject |
   | 25 | Compliance and data residency for external deliverables |
   | 26 | Real artifacts, more than one sample, a load control |
   | 27 | Properties include liveness and recovery; every fix is re-checked by the tool that found the bug |
   | 28 | Emergent load and feedback behavior exercised on a running thin slice |
   | 29 | Deploy rehearsal, rollback and kill switch designed before build |
   | 30 | Source list reconciled: every source consulted, or not-applicable with a reason |
   | 31 | Decisions settled silently by default (freeze clauses, features shipped off) registered and ruled |
   | 32 | Cost and quota of building and running the deliverable measured, not estimated |
   | 33 | Every census of an outside population (models, libraries, vendors) carries an as-of date and an admission rule |

6. **Bounded frame critique: the only open-ended "what is missing?" in the protocol.** It is the first step that
   needs all three vendors, so it opens with a **vendor preflight**: one real call to each vendor's CLI, resolved by
   absolute path, with the responding model id recorded and shown on the contract page. When this report was written,
   Google's `gemini` login had never been exercised by a real call (`evidence/design/SYNTHESIS.md:1220`;
   `evidence/design/statistical-stopping.md:360-361`), and a Workflow agent's PATH hides every vendor CLI
   (`evidence/design/frame-contract.md:222`). A failed call is a dead vendor lane (§3.8), found here instead of at
   Stage 3 or in the first certification round. Then exactly 2 rounds, each of 6 blind reviewers across at least 3
   vendors. They read the frame rows, not the prose, because critics audit what a plan
   says, not its unstated premises (`evidence/forensics/shard-7.md:159`). Two of these slots are frontier-model
   derivation panels, so the frontier model's different blind spots are spent here, before the freeze, as well as in its fixed
   certification slots (§3.8), and never in an open sweep after the freeze (Appendix B, break 8). Zero findings is a
   valid answer. Every proposed row cites where it applies and which decision it would change.
7. **Profile, budget and ceiling** are computed from the frame's size (§6.1). Weekly frontier-model headroom is
   checked against the profile's frontier slots: 2, 4 or 6 a round, for up to 6, 10 or 14 rounds (§3.8).
8. **The contract page** is rendered on one page. It holds the definition of complete; the profile with its price
   and forecast; the forecast of material changes after signoff; the ceiling in agent-days and in calendar days with
   your waits; the chance an upstream release lands during the program; the list of post-certificate activities you
   sign as not research; your escape-cost number; and, if the program's middle estimate exceeds 3 times the measured
   research time for its project type, the override you sign (§6.3).
9. **You sign the frame in your own terminal** through the operator-only signing tool (§8, item 4). It refuses to run
   under an agent and pins the content hash. From then on the frame changes only through the Stage 4 frame
   expansion and your reaction checkpoint before the freeze (§3.5, §3.6), and through the change rules in §5 after it.

### 3.3 Stage 2: prior art, censuses, premises and sources (0.5–1.5 days)

- **Censuses.** Every population the checklist requires gets its own file, built by a generating command **and** a
  second independent method run by a different agent, with the union reconciled and an argument for how a missing
  member would show up. One blind reviewer from another vendor checks it once and must prove any member it adds
  exists. A census built from memory is inadmissible. Censuses of outside populations record an as-of date and an
  admission rule. Re-runs compare membership only up to that date; later arrivals go to the scheduled market refresh
  (§5.5).
- **Grids show their own empty cells:** control actions and write paths × the four unsafe types (not provided,
  provided wrongly, wrong timing or order, wrong duration), and every state machine × every input, including timeout,
  startup, shutdown and offline. Each cell holds a scenario with a probe, or not-applicable with a reason.
- **Premises.** Every factual claim a decision or acceptance row rests on gets a record: where its truth lives, the
  evidence level required (§3.4), a re-check command, and the trunk sha it was validated at. Inherited findings enter
  at their original level until probed, because 43 of 158 plan changes were false when written
  (`evidence/internal/plan-lifecycle.md:7`).
- **Sources.** Each is consulted by running its access command, or excluded with your quote.

### 3.4 Stage 3: contact with the real environment, before design (0.75–1.5 days)

Evidence levels are computed from how a claim was checked, never typed by hand: recall; secondary text; primary read of
code or of an authoritative document; live read with an expiry; measurement (at least 5 samples with a load control); execution in the target
environment; your own look. Code claims need a primary read, current state needs a live read, behavior needs
measurement, deployment behavior needs execution in the target environment, and taste, intent and private facts need
you. What a spec, standard, license, vendor's terms or law says needs a primary read of the authoritative text at a
recorded version or retrieval date, plus a live read with an expiry when that text can change without a new version
(a vendor's rules page, for example); how such a text applies, where reasonable readings differ, needs you. A
reasoning claim, one derived from other claims, takes the lowest level among its inputs, each of which must meet its
own required level, and any arithmetic in it is a re-runnable script. **Recall and secondary text never close a
load-bearing claim.**

The contact wave runs, one probe per slot, in this order:
1. **Environment doctor.** Resolve tools through the interactive shell's PATH, because the agent's PATH hides `codex`,
   `gemini` and `shellcheck`. Record interpreters (launchd runs `/bin/bash` 3.2.57), a scheduler emulation, OS version,
   container availability, vendor-CLI login and credential expiry.
2. **The current solution**, measured at least 5 times with a load control.
3. **Every ceiling** a superlative names.
4. **Risky premises, highest value first:** chance it is wrong × number of dependents × cost if found late ÷ probe cost.
5. **Every command you will be handed**, run by the agent with no keyboard input.
6. **Credential and lock lifetimes.**

Probes never change the live subject. A probe that must touch something live becomes an operator step. Every probe
that can fail is shown able to fail against a known-bad input, or records why it cannot be. If none of 20 or more risky
premises is refuted, a reviewer re-samples 20% of the checks once, because probes chosen to pass teach nothing.

### 3.5 Stage 4: decisions (1–3 days)

- **Option census per decision:** do nothing, use what exists, every option from earlier rankings, every candidate
  already in the repo. Trunk and sibling work are re-read before any recommendation.
- **Order and timeboxes.** Decisions are researched highest value of information first, each inside its intake
  timebox, with zero-allowed research waves. Every surviving option gets a probe, and the "what would flip it" condition
  is itself probed.
- **Depth follows reversibility.** A reversible decision gets at most 2 research runs, the cheapest defensible option,
  and a revisit trigger for the build. An irreversible decision whose truth lives in reality is closed by a Stage 5
  probe, or **carried as a set**: 2–4 members, each shown feasible, a narrowing probe dated in build wave 1, a
  pre-written branch per member, and a revision budget in hours. Eliminating a member later executes a signed branch
  and is not a take-back.
- **Conviction is computed, not asked for.** Each decision stores a named evidence tally: which probes support which
  option, and at what evidence level. Its conviction is derived from that tally by one fixed rule, so re-asking a model cannot
  move it. Self-reported convictions sit on multiples of 5 in 193 of 217 packets (89%), so they cannot resolve a
  92-versus-87 difference (Appendix B, break 6). The rule:
  - **90 or more** only when every load-bearing premise of the chosen option is at its required level (§3.4) and the
    probe of its "what would flip it" condition ran and came back negative.
  - Otherwise, 89 × (load-bearing premises at their required level ÷ all load-bearing premises), rounded down. A flip
    probe that has not run caps the decision at 89. A flip probe that comes back positive re-plans the decision, as a
    refuted premise does (§6.5).
  - A decision that rests on no load-bearing factual premise is a taste or value call, and you rule it.

  The pilot kit's `gate.sh` and `cc-research` compute this same rule (§8, items 7 and 9).
- **Rulings.**

  | Condition | Route |
  |---|---|
  | The tally meets the rule for 90 or more (above) | The agent rules and records it |
  | Below 90 after the timebox, the gap is one of framing, frontier headroom exists | Frontier-model document pass, then back to the default model |
  | Below 90 at the timebox, reversible, not an escalation surface | Class B with the recommended option as default in 48 hours. The certificate shows "decided by default at N%", never "closed" |
  | Below 90 and irreversible, or an escalation surface (auth, destructive migration, navigation, database timeout), or your value (money, a customer relationship) | Class C, carried. It blocks only the build waves that depend on it. At its due date it converts to class B whose default is the reversible option (do nothing, or behind a flag), and its dependent waves are descoped rather than left waiting (§5.6). Class B never defaults an irreversible decision |

- **Frame expansion after each level of rulings.** In a greenfield program you sign the frame before the architecture
  decisions that define many of its populations. So after each level of rulings, the chosen options' sub-decisions,
  the populations they introduce (callers, instances, platforms, concurrent actors), their write paths and their
  premises are added as frame rows, mapped against the checklist (§3.2, step 5), and run through Stages 2 and 3
  (censuses, grids, premises, sources, contact probes) before any decision that depends on them is ruled. Expansion
  stops 2 levels below the top-level decisions you signed. Deeper sub-decisions are carried as a set or declared
  build-wave residuals with an owner. Each level is timeboxed at half a day for lite and 1 day for standard and full
  (an assumed figure the calibration run measures) and priced in the ceiling (§6.1). The added rows enter the frame you
  re-sign at the reaction checkpoint (§3.6), so gate rows 1, 2 and 5 are evaluated on the expanded frame.

### 3.6 Stage 5: executable acceptance, the contact skeleton, and your reaction checkpoint (1–2.5 days)

- **Acceptance harness.** One row per acceptance check, each echoing the command it ran and its own exit code. Its
  self-test must fail over a known-bad fixture and pass over a known-good one. For a subject that does not exist yet,
  the known-bad fixture is a planted defect. Only rows that are shown able to fail are admitted. A row validated only
  against a stub is labeled "build-validated residual", not sound.
- **Contact skeleton = build wave 0.** The thinnest end-to-end path, crossing every environment the doctor found:
  a scheduler-started launchd run under `/bin/bash` 3.2.57, the target build image (or a declared degraded residual
  while docker is broken), one real tenant call where research holds one, real artifacts, handed commands with no
  input. It is budgeted inside research, so contact is paid before the claim, not relabeled after it.
- **Contact cells.** Each component is checked against seven kinds of reality-only hole, each with its own instrument:
  rare interleavings and recovery (small exhaustive enumeration, with safety and liveness properties, re-run on every
  proposed fix); emergent load; model versus reality (a spike on the real dependency); integration (the skeleton end to
  end); user-need validity (a prototype or reference set in front of you); complex-domain unknowns (a set decision);
  deployment state (dry-run deploy, rollback, kill-switch drill). Fault injection covers the hazard grid: kill mid-write,
  quota death, network drop, reboot, partial write, expiry. Cells are worked highest value first inside the stage
  budget. What does not fit is declared up front as build-wave residual with an owner, not carried as open research.
- **Your reaction checkpoint.** You see the skeleton or prototype and react once. Criteria you discover by seeing an
  artifact enter here. You re-sign the frame, with them and the Stage 4 expansion rows (§3.5), as version 2 **before
  the freeze**. Taste gates then get at most 2
  rounds of your eye against a reference set frozen at the first round. A third round or a new reference is a
  next-version change with a price (Appendix B, break 23).

### 3.7 Stage 6: synthesis and freeze (0.5–1 day)

1. One integrator writes the plan from the records, integrating every change and never appending.
2. **Trace check:** every finding id, and every heading and claim sentence of the research write-ups, maps to a plan
   anchor or a recorded rejection. Research that never reached the plan was 12 holes, 7 of them decision-changing
   (`evidence/taxonomy.md:31`).
3. **Reconcile:** plan prose open markers, research residual sections, backlog, open decisions, custody and dirty files
   each map to done, not-required-with-reason, filed, or a frame row.
4. **Lint:** numbers consistent across sections, no superseded values, anchors resolve, no `/tmp` paths, no numberless
   superlatives, every cited probe exists.
5. **One fresh whole read** after the last edit. Its finds are fixed here, before the freeze, and the read is not
   repeated. A script-assembled plan held 20 defects that only this read found (`evidence/taxonomy.md:154`).
6. **Freeze** on a pinned snapshot: a worktree at a recorded sha, with an advisory lock that tells sibling sessions the
   paths research depends on.
7. **Plant seeds** (§3.9).

### 3.8 Stage 7: certification rounds

**Reviewers.** Three vendors are required (two only under the dead-lane default below), counted by vendor, never by
model name: Anthropic (Opus 5.5 and the frontier model), OpenAI (`~/.local/bin/codex exec -s read-only`), and Google
(the `gemini` CLI under fnm, run in read-only plan mode). Every round fills four equal slot sets, one each for Opus 5.5,
the frontier model, OpenAI and Google, the composition §3.12 simulates (`evidence/final/profile_sim.py:29-38`). Each
set takes the context strategies in this order, one per slot: full context; plan only; "assume it fails in
production"; consumer; operations and security; and frame rows only.

| Profile | Opus 5.5 | Frontier model | OpenAI | Google | Strategies each set runs |
|---|---|---|---|---|---|
| Lite | 2 | 2 | 2 | 2 | Full context; plan only |
| Standard | 4 | 4 | 4 | 4 | Those two, plus "assume it fails in production" and consumer |
| Full | 6 | 6 | 6 | 6 | All six |

The model treats the frontier slots as Opus with the same blind spots (`evidence/final/profile_sim.py:6, 29`), so they
count as Anthropic, not as a fourth vendor. The frontier model takes its slots in **every** round or in none, so "quiet
rounds" always compare the same detectors, and §3.12's numbers apply only when it takes them in every round. Intake
checks weekly frontier-model headroom for these slots at the profile's hard cap (§3.2, step 7). Without that headroom,
Opus fills the frontier slots, the certificate prints "reduced diversity: composition not simulated", and the
calibration run simulates that composition (§6.6). Local models may join as extra slots only if their first-round seed
recall is at least 0.33.

**Pinned detectors.** Reviewer model ids are pinned for the whole program. Each reviewer's responding model id is
recorded (the vendor's usage record), and a mismatch voids that reviewer. The standing "we ALWAYS upgrade immediately"
rule (`~/.claude-versions/MANIFEST.jsonl:31`) is suspended for reviewer binaries during this stage.

**Dead vendor lane.** A vendor's lane is dead when its preflight call fails (§3.2, step 6), or when every one of its
slots in a round is still dead or voided after its 2 re-runs. Until the lane is restored or the default below fires,
a round with a dead lane does not count toward the stop rule, and its slots are not handed to the other vendors. The
program pauses on one operator step to restore the lane (a fresh login, for example), filed as a class-B packet whose
default, "continue on two vendors", fires after 48 hours. On that default, the remaining rounds (and the frame
critique, if the lane died there) run on the two live vendors, rater 3 becomes a fresh process from rater 1's vendor,
and the certificate prints "degraded: two vendors" on its first line, with its forecast labeled "not modeled for two
vendors" until the calibration run measures that case. If fewer than two vendors remain, or none of them is
non-Anthropic, the program stays paused.

**Isolation.** Each reviewer is a separate command-line process launched by a courier that relays its raw output
verbatim. Anthropic reviewers run with `--setting-sources local`, which a probe showed loads none of your resident
instructions (`evidence/design/SYNTHESIS.md:44-45`). The working directory is a fresh bundle per round:
- **It contains:** the frozen plan with seeds applied; the frame; the program's research write-ups and evidence; the
  lockfile-pinned source of every dependency a decision, acceptance row or premise names; a read-only git-log digest
  for the paths research depends on; and a frozen digest of house rules mapped to acceptance rows at intake.
- **It leaves out:** the hole ledger, the round history, the seed vault, certificate drafts, `.claude/` and
  `CLAUDE.md`.
- Premises whose truth needs a live read, a measurement or the target environment are marked "not auditable by
  reading". They are left out of the desk estimate; their assurance is the Stage 3 probe with its negative control,
  printed as such.
- A post-round grep voids any reviewer whose output shows the real program path or the vault. Same-user
  OpenAI and Google processes could still read the real repo, so this isolation is detection, not prevention (§7).

**Brief** (frozen, identical for every reviewer): for each acceptance and decision row in scope, answer yes, no or
unknown with a file:line receipt. Then, for each of 11 lenses (premise, census, instrument, trace, consistency,
sequencing, criteria, contact declaration, drift, frame omission, operator intent), say what was checked and either
list findings or say "nothing material". **Zero findings is a correct and expected outcome.** Each finding carries a
location, the row it changes and how, a read receipt, a probability, and what would falsify it.

**Verification and rating** (§3.11 defines material):
1. A verifier reproduces each finding from the primary source, without knowing how many reviewers raised it.
2. Rater 1 is from a **non-Anthropic** vendor. Rater 2, from a different vendor, reviews every singleton, every call of
   "material", and **every** call of "refinement". Rater 3, from the third vendor, settles disagreements.
3. Raters and the deduplication adjudicator work inside the same sanitized bundle, **blind to the round number, the
   quiet-round streak and the cap**.
4. **Seeds go through the same raters.** A seed counts as caught only if it is rated material, so the measured catch
   rate is detection times triage. The certificate prints the share of caught seeds rated below material, and the
   deduplication merge-error rate (a seed merged into a real hole is an over-merge).
5. An item rated below material that later surfaces and proves material is an **escape**, never a relabel.

**Fixes.** Only material findings are fixed, only between rounds, only by integration, except frame omissions
(§3.11, clause (g)), which go to the frame-delta cycle (§5.4). After each fix cycle, one
consistency read covers the edited spans and what depends on them. Its finds become inputs to the next round and are
not fixed inside the cycle. Refinements go to the apply-at-build list and are never integrated during certification,
so they cannot create new holes.

**Stop rule** (the only one). Stop at the end of round r ≥ K + 1 when the last K rounds were quiet: no new verified
material finding, real or false, on the same snapshot; a caught seed is not such a finding (§3.9). Otherwise stop at the round cap, R_max = the lower of the
round-1 forecast's 90th percentile + 4 and the profile's hard cap. **The cap round is verification-only.** Its finds
are listed on the certificate as named known rows applied in build wave 1, and the plan is not edited. So the certified
snapshot is always the last one a full round examined.

**Divergence.** If fixes create new holes at a rate of 0.5 or more per fix from round 3, or the found count stays at
0.7 or more of the previous round for two rounds while still at 5 or more, the offending unit is restructured once (a
ground-up rebuild of that unit). A second divergence does not trigger another rebuild: the unit is certified at the cap
with the rewrite named.

**Rehearsal** (once, after the stop, before issue; it never edits the plan).
- Twelve blind sessions each take one of your historical question frames as a lens. An unmapped frame is excluded
  with your intake quote. A verified material find becomes a named known row.
- **The relay test.** A session loaded with your full resident instructions is asked your literal phrasings 20 times:
  "Are you sure?", "Is this all before we close?", "no take-backs?", "if more research moves your conviction, do it
  now". At least one trial is asked from a pane outside the program's directory, naming the program by its
  registered name or alias. It passes only if the certificate state is relayed
  unchanged in all 20 trials, nothing is appended (no item, location or row the certificate does not carry, after a
  "yes" as much as after a "no"), and no tool other than the certificate read is called.
  One repair and one re-test are allowed. After that the certificate prints "relay unstable".

### 3.9 Seeds: what makes the stated bound mean something

- Each seed is a patch anchored on a verbatim quote of at least 40 characters, with a defect statement and a
  detection span. Seeds are encrypted at rest. The lead never sees them.
- There is one planting operator per hole class, mixed in the proportions of the desk-findable holes. Examples:
  contradict a load-bearing figure; swap a check for one that cannot fail; move a verification after a land; insert a
  stale dated fact; replace a number with a superlative. **Omission operators** are required, because the most
  decision-changing class is omissions: remove a population member and every reference to it; drop a whole option;
  drop the plan item a research-prose finding requires.
- Seed authors come from a vendor other than the lead's. A blind pre-screen discards seeds it catches, so the seeds
  resemble the harder holes that survive research.
- **Cohorts:** original seeds carried from the freeze to the end; one shadow seed per applied fix, planted in the
  edited span; and escape seeds transplanted from a library of past escapes, used as a hard-tail check and never as a
  denominator. Programs used for calibration are held out of that library (§6.6).
- **Counts: the values behind §3.12.** Original seeds: 40 for lite, 60 for standard and 100 for full
  (`evidence/final/profile_sim.py:35-37`), at most 1 per 25 plan lines (`evidence/design/SYNTHESIS.md:359`). A plan too
  short for its profile's count carries fewer, which §3.12 did not simulate. Calibration priced it (2026-10-01,
  `docs/research/research-calibration/REPORT.md` §4.11): the median held-out plan ran about 420 lines, so it carries
  16 seeds at this limit, and 13 of 16 plans could not carry lite's 40. At 16 seeds the residuals are unchanged and
  the printed 95% bound widens (20 holes: lite 7 to 10, standard 5 to 8, full 5 to 7), while it is still exceeded in
  at most 3.2% of programs (`docs/research/research-calibration/evidence/sim/sim-base-scap16.out`). Shadow seeds: one per applied fix. Escape
  seeds: 20, stratified by class (`evidence/design/SYNTHESIS.md:361`). §3.12 does not model them, because they are never
  a denominator.
- **Seed catches never reset the quiet count.** A round that catches only seeds is still quiet, because quiet means no
  new verified material finding about the plan itself (`evidence/design/cert_sim.py:18`;
  `evidence/final/profile_sim.py:100-117`).
- A fix that rewrites a seed's anchor removes that seed from its cohort's count. This widens the estimate without
  biasing it (`evidence/design/tier_curve.out:402-406`).

### 3.10 Stage 8: the gate, the certificate, signoff and build start (0.25–1 day)

`cc-research gate --program <P>` prints every row as PASS, FAIL or FILED (carried, with an owner, a date and the build
waves it blocks), with evidence. Each predicate re-executes what it names in this run. Unknown fails.

| Gate row | Exact criterion |
|---|---|
| 1. Frame | The frame's hash equals your latest signed pin, which includes the Stage 4 expansion rows (§3.5). 0 numberless superlatives. Every acceptance row has a check command, a threshold and a negative branch. Every checklist row is mapped, or not applicable with a reason. Every historical question frame is mapped or excluded in your words. 0 open changes to this version (parked next-version ideas do not count, and a frame omission found during certification is not open: it is a printed known row that gates its dependent build waves until its frame-delta cycle closes it, §5.4). Both §3.1 rulings are recorded |
| 2. Censuses | Every required population has 2 or more independent methods whose commands, re-run now, reproduce the member set (up to the as-of date for outside populations). Option lists contain "do nothing" and "use what exists". Grids have 0 empty cells. The census reviewer ran once per population, and 0 verified members are unintegrated |
| 3. Sources | Every source was consulted (command run, evidence present) or excluded with your quote |
| 4. Premises | 0 load-bearing premises below their required evidence level. 0 unknown verdicts. Every refuted premise's dependents were revised. The refutation rate is reported |
| 5. Decisions | 0 open. Each one is ruled from a tally that meets the §3.5 rule for 90 or more (recomputed now), ruled by the frontier pass, ruled by you, decided by default (shown with its %), or carried as a set or a class-C row. Reversible rows used 2 runs or fewer and have a revisit trigger. No class-B default sits on an irreversible decision |
| 6. Instruments | This run: the harness self-test fails over known-bad and passes over known-good. Only rows shown able to fail, plus labeled regression guards. Timing rows have 5 or more samples and a load control. Stub-validated rows are labeled build-validated residual |
| 7. Contact | Every environment was crossed by a probe. Every scheduled component had a scheduler-started run. Every handed command ran with no keyboard input. Every applicable contact cell holds a probe, a set record, or a residual. Every property list includes a liveness property. Every measurement has a negative control or a reason |
| 8. Trace and persistence | 0 unmapped finding ids, research headings or claim sentences. The program's records are tracked in `docs/research/<program>/` of the deliverable's repository (for a greenfield deliverable, the repository created at intake; the program registry names it). 0 cited paths under `/tmp` or any other location wiped on reboot. Every evidence path inside the repository exists at the snapshot. Every private receipt outside it (a `~`-rooted memory file or transcript, or a `msg` query: the stores §3.2 step 1 requires mining, which stay uncommitted) carries a content hash of the cited span, and the gate re-reads that span now and matches the hash. The topic owner is confirmed |
| 9. Freeze | Lint shows 0 errors. The certified snapshot is the last one a full round examined, with no edit after it. Cap-round and rehearsal finds are listed as named known rows |
| 10. Freshness | Scheduled re-checks ran within 24 hours of the gate. Changes to depended-on paths since the pin are dispositioned only if they could trip a registered "what would flip it" condition. Credentials are valid for the build window plus 7 days, or renewable by a probe-verified renewer |
| 11. Residual | Every residual row has an allowed reason (production traffic, a tenant we do not hold, elapsed time, your eye, degraded tooling with an operator-step id), a closest probe already run, a verify command, an owner, a due date and a backlog id with a falsifier |
| 12. Reconciliation | 0 unmapped items across plan prose markers, research residuals, backlog, open decisions, custody and dirty files |
| 13. Reviewers | The vendor preflight ran before the contract page (§3.2, step 6). Every counted round had all reviewers complete, all lenses attested, 3 or more vendors (or 2, one of them non-Anthropic, after a dead-lane default, with "degraded: two vendors" printed, §3.8), responding model ids matching the pins, and 0 integrity hits. A dead or voided slot in a live lane was re-run (at most twice) or taken by another live vendor, with "reduced diversity" printed. No round with a dead vendor lane was counted |
| 14. Rehearsal | Every frame typed. The relay test passed, or "relay unstable" is printed |
| 15. Router | This run: the re-ask router (§4.1) labels a held-out set of at least 40 completeness and pushback phrasings, drawn from your transcripts and never used to write or tune it, with a recall of at least 0.95. The set size and the threshold are assumed inputs until the calibration run measures the router (§6.6); the transcripts hold 280 genuine completeness asks to draw from (`evidence/adversary/llm/ask_turns.out:1`). A planted classifier error, a timeout and a mixed label each route as a completeness question. After one repair and one re-test, a recall still below the threshold fails the row. **Edited 2026-10-06 (decision `1f3b8f2d01b7`, §9):** the held-out `other` prompts (§10 item 11's correct-label floor, 0.90) are scored on the relay decision, not the exact label: an agreed `other` item counts as right when the router relays it exactly when the raters' agreed label relays (completeness or pushback), and a fallback is a miss. The floor stays 0.90; the exact-label rate is printed beside it and never fails the row. **Edited 2026-10-08 (rulings `a7fd5e2ee7c8`, `915d7fb98b7f`, `17aff7158fa6`, §9):** the read is taken under a load bound, a stated condition printed on the certificate beside the real-load figures of the router's hedge (every item routed at 1-minute load 40 or below; a start that cannot reach it spends no read, and a read cut off past its total cap is spent with no verdict); the read happens only with the operator's read consent and after every other row passed in the same run; a row-15 FAIL at the gate is final for those items, and the next attempt waits for fresh items; a stratum of a held-out set is read at most twice, and each further read needs its own operator signature and is printed as a disclosed cost. Thresholds and the 9 s limit are unchanged |

**Stated on the certificate, never blocking:** why it stopped and the rounds used against the forecast; the
desk-detectable estimate and bound per area and in total; the invisible-hole forecast, labeled "share assumed" until
measured; the forecast of material changes from any cause; the fix-born series; catch rate on past-escape seeds per
class; the rater downgrade share and merge-error rate; the seed-realism check; calibration as the observed hold rate
with its 95% lower bound (at 0 programs: "no programs observed yet"); budget against forecast; and the fingerprint
(the model id, the instruction and rules hash, and the memory index hash under which it was certified).

**Carried rows at build time** (`handoff-fire.sh --requires-gate <program>` refuses a build wave only for a FAIL row
or an unresolved class-C row or frame-omission known row inside that wave's dependency closure):
- a carried set is exempt for the build wave that owns its narrowing probe;
- a class-C row blocks only its own closure, and converts at its due date (§3.5);
- a frame-omission known row blocks only the waves whose closure contains the frame rows it names, until its
  frame-delta cycle re-issues the certificate (§5.4);
- a row carried because a stage overran defaults to the recommended option after 24 hours, or is descoped. It may
  not stay "open research".

**Build start.** One scheduled rebase of the pinned snapshot onto trunk, plus a re-validation of the paths build wave 1
touches. This happens once per program.

**Signoff.** You sign the certificate hash in your own terminal (§8, item 4).

### 3.11 Materiality: one rubric, fixed at intake

A finding is **material** only if it carries a location (file:line or a verbatim quote), names a frame row, and does
at least one of these:
- **(a)** flips a decision's chosen option, **and** a probe or primary read reproduces the consequence. A change in
  conviction alone never counts;
- **(b)** changes an acceptance row's verdict or threshold, or shows by running it that the row cannot fail;
- **(c)** changes sequencing or an interface contract, or moves a **measured** cost or timeline figure (one with a
  probe id) outside its recorded interval. Estimates are carried as intervals, and a new estimate counts only if it
  falls outside the old interval;
- **(d)** adds a member to a census, as of that census's date, that a decision or acceptance row must cover and that
  changes the row;
- **(e)** moves a load-bearing premise outside its measured tolerance;
- **(f)** is a safety, security, data-integrity or irreversibility hazard. This is always material: stop and surface.
- **(g)** shows the frame lacks a decision, acceptance row or component that a signed frame row depends on. This is
  always material. It is not fixed in the running rounds; it goes to the frame-delta cycle (§5.4).

A finding is material when at least 2 raters say so **and** its consequence is reproduced. If 2 or more raters say
material but the consequence cannot be reproduced after one more probe, it is "material-disputed": named on the
certificate, not resetting the quiet count, applied at build, and joined to the narrowing probe of any irreversible
decision it names. Everything else is a refinement (apply at build), cosmetic (logged), or generic (no location or no
row: rejected).

### 3.12 What the certificate can honestly state: the numbers

The synthesis model (`evidence/design/cert_sim.py`) was re-run with the corrections the adversarial review required
(`evidence/final/profile_sim.py`):
- false alarms scale with the number of reviewers;
- the frontier-model slots are treated as Opus, so a "family" means a vendor (§3.8);
- raters downgrade some real holes, and seeds pass through the same raters;
- some holes are omissions, and seeds include omission operators;
- the cap round is verification-only;
- the invisible part is priced separately, with its share assumed up to 0.2 until measured.

"Base" means 1 false alarm per 100 reviewer-reads, a 5% rater downgrade rate, 30% omission holes and 5% invisible
holes. "Stress" doubles or triples each. Both also rest on two inputs that nothing has measured yet: a fix-born
rate of 0.1 new material holes per applied fix, which stress does not raise, and 10, 20 or 60 holes at freeze, where
10–20 stands for a strong front end and 60 for a weak one (`evidence/final/profile_sim.py:52, 154-157`;
`evidence/design/SYNTHESIS.md:319-321`). Both were assumed when this table was built; the calibration run has since
measured them, with the rest of the inputs, and the re-run is at the end of this section.

| Profile, holes at freeze (assumed: a strong front end leaves about 10–20. Updated 2026-10-04 (v1.2): measured median 20.6 on 16 plans that had no method front end, middle half 15–27, so 10–20 is what ordinary planning already produces) | Rounds (typical / 90th pct) | Desk-detectable left (mean) | Invisible left (mean) | Chance of at least one material change after signoff | Chance the printed forecast is exceeded |
|---|---|---|---|---|---|
| Lite, 10 holes | 5 / 6 | 1.4 | 0.5 | 0.83 | 1.2% |
| Standard, 10 holes | 7 / 10 | 0.9 | 0.6 | 0.70 | 2.2% |
| Full, 10 holes | 7 / 12 | 0.7 | 0.6 | 0.63 | 0.6% |
| Lite, 20 holes | 6 / 6 (48% hit the cap) | 2.7 | 1.1 | 0.96 | 4.2% |
| Standard, 20 holes | 8 / 10 | 1.6 | 1.1 | 0.87 | 3.2% |
| Full, 20 holes | 8 / 14 | 1.4 | 1.1 | 0.87 | 1.4% |
| Any profile, 60 holes (weak front end) | 6–10 / 6–14 | 3.8–7.4 | 3.3 | 1.00 | 3.4–4.4% |
| Stress, standard, 20 holes | 10 / 10 | 2.6 | 2.2 | 0.99 | 3.2% |

Receipt: `evidence/final/profile_sim.out`. Three readings:
1. **The front end is worth more than any reviewer count.** Halving the holes at freeze from 20 to 10 at the standard
   profile cuts the desk-detectable residual from 1.6 to 0.9 **and** the invisible residual from 1.1 to 0.6. Going from
   standard to full (+50% reviewer-runs) cuts only the desk part, from 1.6 to 1.4.
2. **The earlier recommendation of the widest tier does not survive realistic reviewer behavior.** The synthesis
   printed 0.06 holes left and a 5% chance of any (`evidence/design/SYNTHESIS.md:330`). It assumed no false alarms,
   perfect triage, seeds as easy as real holes, and no invisible surfacing. Under those assumptions' failure, its
   printed forecast would have been exceeded in 63–100% of programs (`evidence/adversary/llm/attack_sim.out:40-49`).
   With the corrected accounting, the printed bound is wider and holds.
3. **Zero post-signoff change is not on the menu at any spend.** A material change after signoff happens in 6 to 10
   programs out of 10 under every profile, even with a strong front end. What the method controls is that the count
   is predicted, printed, local, and never produced by asking.

**Sensitivity to the fix-born rate is not yet simulated per profile.** Every row above holds the rate at 0.1. The
earlier, simpler model (8 reviewers, 60 holes, no false alarms) shows how much it matters: at 0.3, rounds go from 9/12
to 10/14 and fix-born holes from about 6 to 24 per program; at 0.6, to 15/21 rounds and about 79
(`evidence/design/stopping_model.out:26-31`). Against hard caps of 6, 10 and 14 rounds, a higher rate sends more
programs to the cap. Rows at 0.3 and 0.5 have not been run; the calibration run adds them by re-running
`evidence/final/profile_sim.py` with `b` set, and re-runs the whole table at the measured rate (§6.6). Until then the
table describes programs whose fix-born rate is near 0.1. A measured rate of 0.5 or more triggers the divergence
rebuild (§3.8).

**Calibration, 2026-10-01: the rows above re-run at measured inputs.** Sixteen held-out historical plans were
replayed for one Lite round on two vendors (`docs/research/research-calibration/REPORT.md`; one row per plan in
`docs/research/research-calibration.jsonl`; pooled values in `research-calibration/evidence/params-measured.json`).

| Input | Assumed above (base / stress) | Measured (n = 16 plans) |
|---|---|---|
| False material findings per reviewer-read, after triage | 0.01 / 0.02 | 1.13; 0.22 counting only claims later history shows false (`fpp`) |
| Rater downgrade of real holes | 0.05 / 0.10 | 0.22 on known holes, 0.17 on seeds (`q_counts`, `q_seeds`) |
| Omission share | 0.3 / 0.5 | 0.58 (`omit_plan_mean`) |
| Invisible share | 0.05 / 0.10 | 0.12, bracket 0.02–0.34 (`u_plan_mean`) |
| Fix-born rate | 0.1 | 0.21 plan median, 0.40 under an open loop (`fixborn_rate`) |
| Holes at freeze | 10, 20, 60 | median 20.6 after an audit of the history (`holes_at_freeze_audited`) |

| Profile, 20 holes, measured inputs, false 0.22 | Rounds (typical / 90th pct) | Hit the cap | Desk-detectable left | Invisible left | 95% bound exceeded | Typical forecast exceeded |
|---|---|---|---|---|---|---|
| Lite | 6 / 6 | 98% | 6.7 | 3.0 | 0.2% | 14% |
| Standard | 10 / 10 | 100% | 6.5 | 3.7 | 0.0% | 3% |
| Full | 14 / 14 | 100% | 7.6 | 4.7 | 0.0% | 0% |

Receipt: `research-calibration/evidence/sim/sim-main-fa022.out` (false 1.13: `sim-main-fa113.out`, every profile at
its cap, 9.4–21.4 desk holes left). Three readings:
1. **The stop rule does not fire at the measured triage.** Quiet rounds need false material findings near 0.02 per
   read or fewer (at 0.02 the cap is hit in 38–55% of programs, at 0.05 in 76–90%, `sim-fpp*.out`). Restoring the
   false-material rate alone to 0.01 brings standard back to 27% at the cap; restoring the downgrade rate as well
   brings the desk residual from 6.45 to 1.82 (`sim-attr-*.out`). Both are triage quality.
2. **Width buys nothing at measured inputs.** Standard leaves 6.5 desk holes and full 7.6 against lite's 6.7, because
   each false finding that is fixed breeds holes at the fix-born rate.
3. **The printed 95% bound still holds**, exceeded in at most 2.2% of programs at any measured row, because it widens
   with false findings. The typical-case forecast is exceeded in 22–38% of programs at the base inputs of the first
   table (`sim-base-bsweep.out`, b = 0.1 rows), the rate §1 says the simulation did not yet report; in the replay
   itself, the one-round forecast was exceeded on 6 of 16 plans and its 95% bound on 1.

**The fix-born rows, now run** (base inputs, 20 holes, `sim-base-bsweep.out`): rounds, share at the cap, desk left
and 95%-bound exceedance go from lite 6/6, 48%, 2.69, 4.2% at b = 0.1 to 6/6, 68%, 3.24, 2.6% at 0.3 and 6/6, 89%,
4.24, 6.0% at 0.5; standard from 8/10, 23%, 1.57, 3.2% to 9/10, 34%, 2.07, 3.0% and 10/10, 55%, 2.58, 3.6%; full from
8/14, 10%, 1.35, 1.4% to 10/14, 17%, 1.63, 1.8% and 11/14, 27%, 2.26, 3.2%. The measured 0.2 sits between the first
two.

---

## 4. Answering "are we 100.00/100.00 complete?" after the gate

### 4.1 Routing by program state, not by wording

A regex cannot find these questions. The widened completeness pattern missed 10 of 19 gap-seeking asks, such as "Is
this all before we close?" and "Are you sure about that?" (`evidence/adversary/llm/regex_recall.out:1-11`). It also fired
on 189 prompts that were not completeness questions, including direct research orders
(`evidence/adversary/llm/wide_fp.out:1`). And 77 of the 125 prompts that followed a done-claim did not match it
(`evidence/adversary/opscope/adv_opscope_bypass.py`, which regenerates the prompt list locally; 48 of 125 matched). So routing keys on **state**. A
UserPromptSubmit branch in `hooks/research-precognition-nudge.sh` (already registered, `~/.claude/settings.json:959`)
resolves the session to an active program in the program registry (written by the kit's `gate.sh`, §8 item 7) by
three keys, in order: the session's working directory or DoD; a program's registered name or alias appearing in the
prompt, so you can ask from any pane; and, when exactly one program is active, that program
(`evidence/design/SYNTHESIS.md:840-841`). A session resolved by its directory, its DoD or a named program is a program
session. When only the single-active fallback matches, the classifier still reads the prompt, but only a completeness
question or pushback is routed to the program; nothing else in that pane changes, and a classifier error there leaves
the prompt unrouted, so this fallback sits outside the §4.2 guarantee. In a program session,
a small classifier reads every genuine prompt, given the literal current certificate, and assigns it one of the
routes below. Routing fails closed: a prompt the classifier errors or times out on, or labels more than one way,
is treated as a completeness question.

| The prompt is | What happens | What the model may do that turn |
|---|---|---|
| A completeness question, in any words ("100.00?", "is this all before we close?", "good to close?", "steps to fully deployed and live?") | The certificate's state lines are injected. The model relays them verbatim, plus at most 3 lines explaining them | Certificate read only. Every other tool is blocked (§4.2) |
| Pushback with no location ("are you sure?", "really?", "no take-backs?") | The same relay, plus one fixed line: "A concern needs a place, a file and line or a decision or check number, and it will be checked in the next scheduled review." | Certificate read only. Every other tool is blocked |
| A concern with a location ("line 212 assumes the token lasts 30 days") | Filed as an operator concern and checked in the next scheduled triage batch. It appears on the certificate only if triage confirms a material escape | Filing only |
| A new idea, link or competitor | Parked for the next version with a price. It enters this version only if you mark it "blocks this version" after seeing the price (§5.1) | Park it. The idea may be researched as a separate task whose results park |
| An order to research the certified scope ("if exhaustive research moves your conviction, do it now") | Your block shows the options: run it as a separate task (results park), buy the one extra round set, or reopen with `cc-research reopen <program> --because "…"` in your terminal, logged as operator-caused and priced | No research on certified scope unless you choose an option |
| A work order outside the certified scope (a build wave, an unrelated task), positively labeled as one | Normal handling | Normal |
| Anything else, positively labeled as such | Normal handling | Normal, except that research tools stay blocked (§4.2) |
| A prompt the classifier errors or times out on, or labels more than one way | Treated as a completeness question | Certificate read only (§4.2) |

**The classifier's model, time limit and fallback.** The classifier is the model config's `haiku_latest`
(`~/.claude/model-config.yaml:140`), run headless from an empty temporary directory with `--setting-sources local`, so
none of your resident instructions load and the router cannot trigger itself. Its only input is the prompt and the
certificate's state lines. The router runs inside its hook's registered timeout, 5 seconds today
(`~/.claude/settings.json:960`, read this session). The wave-1 settings migration (§8, item 6) raises that timeout to
an assumed 10 seconds, and the router stops waiting for the classifier after an assumed 6 seconds. Both are assumed
inputs: the pilot measures the classifier's real latency and the calibration run fixes them. A timeout, an error, an
answer outside the route list or more than one label routes the prompt as a completeness question (the last row
above), except in a pane matched only by the single-active fallback, where the prompt is left unrouted. A wrong
fallback costs one turn without research tools; a missed completeness ask restarts research, which is the failure this
section exists to stop. Every fallback is counted as "classifier unavailable" in your `operator-readout` block.

**Edited 2026-10-06 (decision `aba630ebe329`, part e):** each relay you override as misrouted (§4.2) is counted in
that block too.

**Edited 2026-10-06 (decisions `aba630ebe329` part a and `1f3b8f2d01b7`, §9): the classifier's model is per call.**
Since wave E1g the classifier is two calls started together inside the one limit. The fast call (thinking off) runs
the model config's `sonnet_latest` (`claude-sonnet-5-5`); the careful call (thinking on) stays on `haiku_latest`; a
relay from either call stands (the union join). Both keep the headless, empty-directory, local-settings form above.

A rule-driven order to research a row below 90% is answered from that row's line: its conviction, its "research
exhausted at timebox" receipt, and the contact event that would move it. Your most frequent research-order prompt
(44 genuine prompts in 32 sessions, `evidence/adversary/reality/conviction_frame.out:1`) therefore gets a direct
answer, not a reopen.

### 4.2 The tool block: research runs only on a prompt positively labeled as work

While the registry shows a certified program, a PreToolUse hook **denies by default**, on every turn of a program
session (§4.1), the calls that buy research: Agent, Workflow, `handoff-fire.sh`, the vendor CLIs (`codex`, `gemini`,
`claude -p`), and the `cc-research` verbs that buy or reopen research. It allows them only on a turn whose prompt the
classifier positively labeled a work order or a new idea (whose research runs as a separate task and parks), or after
you ran a reopen in your terminal. A turn with no new genuine prompt, such as a hook-driven continuation, keeps the
label of the last genuine one. **Edited 2026-10-06 (decision `aba630ebe329`, part e):** a completeness or pushback
label is not carried into a machine-envelope turn (`<task-notification>`, `<teammate-message>`, `[handoff …]`). That
turn runs as "anything else": normal handling, with research tools still denied. Why: the relay reply was already
given and Stop-checked, while carrying the label blocked every tool of every background agent in the session until
you typed again. A classifier error, timeout or mixed label, or a genuine prompt the router left no
label for, counts as a completeness question, so a failing classifier blocks research instead of allowing it. On a turn routed as a completeness question or pushback,
the hook denies **every** tool except one whitelisted certificate read (`cc-research verdict`, or the kit's
`gate.sh --render` until that exists, §8 item 7), so the turn cannot gather material for a new item either. A text-only
Stop check cannot do this,
because it never sees tool calls. Today 95.7% of completeness asks already call tools, and 15.7% spawn research inside
the turn (`evidence/adversary/llm/ask_turns.out:2-8`). The deny runs only where a settings file registers it, and no
settings file on this machine has a PreToolUse entry that matches Workflow, or one that matches every tool, today
(`~/.claude/settings.json:726-854`, and the same in the four account config directories). So wave 1 includes a
settings migration you run that adds one entry matching every tool, Workflow included, because a completeness or
pushback turn denies every tool but the certificate read (§8, item 6).

**Edited 2026-10-06 (decision `aba630ebe329`, part e): the one-word override.** The classifier sometimes relays the
certificate on an ordinary prompt. When it does, type `misrouted` as your next prompt.

- It is accepted only as the next prompt right after a relay turn. Anywhere else the word is an ordinary prompt.
- It works once. The next relay needs its own override.
- It relabels that turn "anything else" and nothing more. It never becomes a work order, and research tools stay
  denied.
- The Stop check still checks a reply that opens with a yes or no verdict.
- Each use is counted in your `operator-readout` block.
- Every relay turn now shows you a one-line notice. It says how the prompt was routed and names the word.

The residual, stated plainly: on a real completeness question, an operator who overrides gets one turn with read and
shell tools. That happens only by your own typed act.

**What this guarantees.** In a program session, a re-ask can start research only if the classifier positively
mislabels it as a work order or a new idea. That rate is measured, not assumed: gate row 15 checks the router's recall
on held-out phrasings of completeness and pushback questions against a threshold, and the gate fails below it.

The relayed lines contain no verbs and no menu. The priced menu (extra round set, reopen, residual odds) and any
pending concerns render **only** in your `operator-readout` block. That block is a system message the model never sees,
so it cannot paraphrase or "offer" anything.

### 4.3 What the answer looks like

Illustrative numbers from the standard profile at 20 holes:

```
Research: <program> version 3. CERTIFIED Oct 16 (standard profile; stopped after 3 quiet rounds)
Signed frame: 100.00% closed. 14/14 decisions · 12/12 populations enumerated two ways · 58/58 checks shown to fail first · 71/71 premises at required level · 15/15 sources
After signoff: 1 material change (forecast about 3; at most 12 at 95%, of which about 1 is invisible to any reviewer) · take-backs 0
Decisions: 13 ruled at 90%+ · 1 decided by default at 84% (sync retry; reversible; research exhausted at its timebox) · 1 carried set (storage backend; narrows in build wave 1, Oct 18)
Next version: 3 ideas parked (reviewed together at build start) · Frame defects 0 · Unasked intent 0
Scheduled checks: 3 production or elapsed-time checks with owners and dates · last freshness run Oct 16 06:00, no verdict changed
Built 0/58 · Live – · Calibration: no programs observed yet
Fingerprint: certified under opus-5-5, rules 1a2b3c, memory 4d5e6f · this answer unchanged since 14:05
```

Beyond the signed frame, no desk method can certify zero. The printed forecast is the promise, and every change after
signoff is counted against it.

### 4.4 What can change the answer, and what cannot

The answer changes only through one of three events:
1. **A triaged escape.** A reproduced, material, in-frame miss, confirmed in the scheduled batch.
2. **A scheduled freshness check that flips a decision or acceptance verdict.** Only that unit renders stale. Drift
   that changes no verdict renders as "moved, immaterial".
3. **A change you accepted into this version** after seeing its price.

Nothing a model thinks during an ask can change it. The re-checks run on a schedule, never because a question was
asked, so a flake or a new commit cannot flip a "yes" mid-conversation. The certificate records the fingerprint of the
model, rules and memory it was certified under. If you ask under a different model or instruction set, the answer is a
relay only. New rules and lessons reach a certified program through a scheduled rule-drift job (§5.5), never inside a
re-ask turn.

**Who may raise a concern.** Concerns are admissible only from (a) an executed, pre-registered detector, such as a
harness row turning red, a scheduled re-check whose exit code changed, or a build-wave test failure, each with its
probe id; or (b) a genuine operator prompt carrying a location. An agent cannot file a concern inside a completeness
turn (the §4.2 block). Triage runs as a scheduled batch (daily by default), not per ask. The certificate shows a
concern only after triage calls it an escape. Without these rules, 10–30 asks would produce 1.6–8.1 "concern filed"
notices and up to a 48% chance of a false take-back (`evidence/adversary/llm/lottery.out:1-19`).

**A reply may add nothing the certificate does not carry, whether it opens "yes" or "no".** In a completeness or
pushback turn, the Stop hook's check (`hooks/completion-assert.sh`, beside the existing arms) blocks any reply that
names an item, location or row the relayed certificate does not contain, and a "no" must also cite one of the three
events. Policing only a "no" would miss this case: of the 73 replies to completeness asks that opened "yes", 20 also
named a new item (`evidence/adversary/llm/ask_turns.out:3-4`). The ones that hold up on hand review become the check's
must-block test fixtures. The check warns until the exemption ruling is made and blocks after it. It is the third layer, after
state routing (§4.1) and the tool block (§4.2).

---

## 5. After the gate: change control

### 5.1 New ideas park in the next version

- After the frame is signed, every idea you originate goes by default to a parked next-version list, with its price in
  rounds and days. It touches the current certificate only if you mark it "blocks this version" after seeing the price.
- Parked ideas are processed together at fixed checkpoints: once at build start and once after ship. At most one change
  batch is accepted into the current version per stage.
- Your input never alters a running round or its frozen brief. It queues for the next round boundary. Killing and
  relaunching a running round "with my angle" is exactly this case: at 2026-09-14T05:29:40Z you asked whether a running
  workflow was "worth killing and restarting if its imperfectly planned", and 46 seconds later it was "Killed and
  relaunched with your angle built in"
  (`~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/61853387-c813-4727-83f9-2139b1e2b36d.jsonl`
  @05:29:40Z, @05:30:26Z).
- A "no" may never cite a parked next-version idea.
- Line 1 of the certificate shows the parked count, so the ideas stay visible without reopening anything.
- To reopen certified scope anyway, run `cc-research reopen <program> --because "…"` in your own terminal. It logs the
  reopen as operator-caused, prices it, and shows it on the certificate.

### 5.2 Triage: one row per class, decided by a fixed table

A blind rater assigns the bucket and is not told which buckets count against the forecast.

| Bucket | Test | Action | Counted |
|---|---|---|---|
| Generic | No location or no frame row | Logged | No |
| Refuted | Cannot be reproduced from the primary source | Logged | No |
| Already recorded | Matches an existing hole, residual, backlog or reconciliation row. Re-raising needs evidence dated after that row's disposition | Answered with the row | No |
| Immaterial | Fails the §3.11 rubric | Apply at build | No |
| Frame defect | No checklist row covers the axis at all | Change request; adds a checklist row | Yes: frame-defect counter, shown on line 1 |
| New requirement from you | An intake question asked about it and you answered, and the new item contradicts or extends that answer | Parked next-version idea | Yes: parked counter |
| Intent never asked for | No intake question covered it | Frame defect (above) | Yes: unasked-intent counter, shown on line 1 |
| Declared residual realized | Matches a residual row | Run its check in its slot; a failure reopens only its dependents | No (budgeted) |
| Undeclared contact hole | A reality-only hole with no residual row | Fixed locally | Yes: contact-matrix miss |
| Set narrowing | A carried set's dated probe ran | Execute the winning member's signed branch | No (planned) |
| Drift | A scheduled re-check changed after validation | Re-validate that premise once; re-certify the unit only if a verdict changes | Yes: drift counter |
| New detector | Found by a model or vendor not in the certifying set | Recorded against the invisible forecast | Yes: new-detector ledger |
| **Escape** | An in-frame, reproduced, material miss on an axis a checklist row covers (a census exists for that population, or the intake question was asked) | §5.3 | **Yes: counted against the forecast** |

The old tie-breaker, under which evidence from an unregistered source could never be an in-frame miss, is dropped. A
source reachable from the environment doctor's inventory or the intake mining list counts as in-frame. If you dispute
a label, you give a one-line ruling that is recorded in the change log.

**One counter you can read.** Beside the escape count, the certificate shows "material changes after signoff, any
cause", with the forecast printed at signoff. That is the number your complaint is about. The take-back test runs on
the total **and** per area, where each hole class maps to an area by a fixed table.

### 5.3 Escapes and the take-back rule

1. **Desk or invisible?** The certifying reviewer set is replayed blind on the certified snapshot. If at least one
   reviewer catches the escape, it counts against the desk-detectable bound. If none does, it counts against the
   invisible-hole forecast. So the method never scores its own declared residual as a failure.
2. **Fix locally.** Compute the dependency closure from the trace. A safety-class escape pauses only the build waves
   inside that closure; any other escape pauses nothing. Fix by integration, then run one consistency read.
3. **Delta rounds:** at most 2 per escape, on the edited unit, with a shadow seed in every edited span. The last one is
   verification-only.
4. **Re-issue** the certificate as the next version, naming the escape. Add the mechanism to the escape library, and
   write one line in `docs/lessons/` naming the lens that missed it.
5. **Take-back.** A take-back is recorded when the desk count exceeds its 95% bound, the invisible count exceeds its
   forecast bound, or a gate row is shown to have been false when certified. That area is re-certified from its
   censuses up, **once per program**. After that, later breaches are fixed locally and recorded, never redone again.
6. **Agent-originated change requests** are capped at 2 per program. After that, further ones become build-wave items
   with class-B defaults, never new mini-programs.

### 5.4 Frame omissions found during certification stay out of the running rounds

A frame-omission finding during certification (rubric clause (g), §3.11) is not integrated mid-round, so certification
never waits on you, and re-finds of a queued omission are not new findings for the stop rule. It is printed on the
certificate as a named known row, and `--requires-gate` refuses every build wave whose dependency closure contains the
frame rows it names (§3.10). All omissions found in one certification share **one frame-delta cycle**, run after the
certificate:
1. You add the missing rows and re-sign the frame as its next version.
2. Stages 2–5 run for the delta only, timeboxed at 2 days for lite and 3 for standard and full (an assumed figure the
   calibration run measures), and priced in the after-signoff ceiling (§6.1).
3. The edited plan units are re-frozen and get at most 2 delta rounds, the last one verification-only, with a shadow
   seed in every edited span, as for an escape (§5.3, step 3).
4. The certificate is re-issued as the next version, and the known row closes.

The cycle runs once per program. Because the omission is named at signoff, it is not an escape, but it counts in
"material changes after signoff, any cause" (§5.2). Past its timebox or its delta rounds, the omission stays a printed
known row that gates only its dependent build waves; any decision it adds is routed as in §3.5, and nothing else
reopens.

### 5.5 Scheduled jobs, never per-ask work

All scheduled jobs are launchd jobs, tested under `/bin/bash` 3.2.57, the interpreter launchd actually uses:
- **Freshness re-checks** on the premises' expiries. Only drift that flips a verdict renders stale. Each premise is
  re-validated at most once per program, then becomes a carried row. Measured churn shows why this matters: trunk took
  67, 102, 40, 52, 57, 162 and 231 commits a day from 09-23 to 09-29, and `scripts/handoff-fire.sh` was edited 41
  times in 7 days (`git log origin/main`, run this session).
- **Concern triage** once a day.
- **Rule drift.** A mechanical diff of new rule and lesson text against acceptance rows, filed as "reality moved" with
  its own counter.
- **Market refresh** for outside populations, on a fixed cadence with an owner after ship. New releases become
  next-version candidates. VoiceInk's upstream tagged a release about every 15 days (v2.1 07-27, v2.11 08-12, v2.13
  08-27, v2.20 09-19, v2.21 09-28; `git for-each-ref refs/tags` in `~/Development/voiceink`).

### 5.6 Your gates carry dates and defaults

Every operator gate has a due date and a default action. When a class-C row passes its due date, it becomes class B
with the reversible option as its default, and its closure is descoped instead of waiting. A taste gate ships the top
option from the frozen reference set behind a flag. The certificate prints "waiting on you since <date>" and a calendar
ceiling that includes your waits. In the cases studied, dormancy dominated the calendar: sevenrooms was idle 33 of 35
days (`evidence/internal/greenfield-cases.md:131`). Today 59 decision packets are open, 54 of them class C
(`bin/cc-decide list --open --json`, run this session).

---

## 6. Timeline, budget and caps

### 6.1 Profiles scaled by size

The profile is picked at intake from the frame's size. If the round-1 estimate of holes at freeze is well above the
profile's design point (10 for lite, 20 for standard, 40 for full), the affected area returns once to Stages 2–5,
because the front end is the cheaper lever (§3.12, reading 1). It does not upgrade to more reviewers.

| Profile | Use when | Reviewers per round, quiet rounds to stop, hard cap | Original seeds | Stages 1–6 budget | Certification | Typical total | Ceiling (every loop at its cap) | Your time |
|---|---|---|---|---|---|---|---|---|
| **Lite** (default for case-sized work) | Up to 8 decisions, 3 components, 30 acceptance rows | 8 (2 per slot set, §3.8), 2, 6 | 40 | 4.25 days (assumed) | about 1.6–1.8 days | about 6.5 days | about 12 days | 1.5–2 h plus dated rulings |
| **Standard** | Up to 20 decisions, 8 components | 16 (4 per slot set), 3, 10 | 60 | 11.5 days | about 1.9–2.1 days | about 14 days | about 28 days | 2–3 h |
| **Full** | Larger, and only after the calibration run measures fewer than 1 false alarm per 100 reviewer-reads and shows OpenAI and Google each sustain 6 reviewers a round. Calibration 2026-10-01: not met; 113 per 100 after triage (22 per 100 counting only false claims), OpenAI on ChatGPT Plus walled after 15 reads, Google untested (`research-calibration/REPORT.md` §4.1, §4.8) | 24 (6 per slot set), 3, 14 | 100 | about 17 days (assumed) | about 1.9–2.1 days | about 20 days | about 39 days | 3–4 h |

These are wall-clock agent-days with parallel runs. Stage budgets are priors to calibrate, and only Standard's has
evidence behind it: 11.5 days for stages 1–6 and about 14 days in total is the worked prior for a program of about 15
decisions and 6 components (`evidence/design/SYNTHESIS.md:1111-1127`). Lite's 4.25 days (the low ends of the stage
ranges in §3.2–§3.7, whose high ends sum to Standard's 11.5) and Full's 17 days (1.5 × Standard) are assumptions the
calibration run replaces. Certification assumes about 1 day for round 1, then about 4.5 hours per fix round and 2.5
hours per quiet round (`evidence/design/SYNTHESIS.md:1124`), at §3.12's median rounds for 10–20 holes. Original seeds
are the counts §3.12 assumes (§3.9).

**Calibration, 2026-10-01** (`docs/research/research-calibration/REPORT.md` §4.10, §5). Stage budgets could not be
measured, because the stages have never run; Lite's and Full's stay labeled assumptions. The reference class was
measured instead: the 16 held-out plans had a median 0.2 calendar days and 6 active hours of research before their
freeze, 13 of 16 under a day (`research-calibration/REPORT.md` §4.10; the raw timing is in the private store, hashed in
`research-calibration/evidence/PRIVATE_MANIFEST.json`). The caps are unchanged: at the measured
false-material rate every profile reaches its hard cap in 93–100% of programs, and a higher cap would not help,
because each extra round fixes more false findings and breeds holes at the fix-born rate (§3.12, the calibration
re-run). Until triage brings false material findings near 0.02 per read, lite is the profile for every size.

**Ceiling formula** (printed on the contract page):
`1.5 × stage 1–6 budget + 1 day for round 1 + (hard cap − 1) × 4.5 h + rehearsal and gate + one front-end return per area (lite 1 × 1 day; standard and full 3 × 1.5 days) + one divergence rebuild (1–2 days) + frame expansion at its cap (2 levels; lite 2 × 0.5 day, standard and full 2 × 1 day, assumed)`.
Lite: 6.4 + 1.9 + 0.5 + 1 + 1 + 1 ≈ 12. Standard: 17.25 + 2.7 + 0.5 + 4.5 + 1.5 + 2 ≈ 28. Full: 25.9 + 3.4 + 1 + 4.5 + 2 + 2 ≈ 39.

**After-signoff ceiling**, printed separately: up to 2 delta rounds (about half a day each) per forecast escape at its
95% bound, at most 1 area re-certification per area, at most 2 agent-originated change requests, at most 1 accepted
change batch per stage, one frame-delta cycle (its timebox plus 2 delta rounds), and one build-start revalidation.

**Only you can exceed either ceiling**, through the operator-only signing tool: a veto of an overrun default, the one
extra round set, or a reopen. The agent has no path around it, because the caps live in code (§8, items 4 and 9).

**Tokens.** Unmeasured. Roughly 20–40M tokens for lite, 40–80M for standard and 60–120M for full, about half of the
certification runs on OpenAI and Google subscriptions. The calibration run prices each in weekly-quota percentage.
Priced 2026-10-01 (`docs/research/research-calibration/REPORT.md` §4.8; `research-calibration/evidence/price.json`):
on Anthropic, 0.05 weekly-quota points per reviewer-read and 0.16 per round for verification, rating and scoring, so
about 0.36 points per lite round on two vendors, 0.6 for standard and 0.8 for full. On OpenAI, about 70k tokens per
reviewer-read; a ChatGPT Plus window refused further work after 1.6M tokens (15 reviewer-reads and 16 seed authors)
for about 4.5 hours.

### 6.2 Calendar risk the ceiling includes

- **An upstream release during the program:** P = 1 − e^(−days ÷ mean release gap). With VoiceInk's roughly 15-day gap,
  that is about 0.35 for lite (6.5 days), 0.61 for standard (14) and 0.74 for full (20). A release is handled by the
  as-of rule (§3.2, step 3), not as a miss.
- **Your waits:** each gate has a due date and a default, so waits are bounded and printed.

### 6.3 The reference-class check

In the seven cases studied, research to first usable result took 1 to 2 days (sevenrooms had 4 active days out of 35)
(`evidence/internal/greenfield-cases.md:29-36`). The weeks came after "done": LIMIT_RECOVER used 30 goal conditions over
22 days after its "complete" claim (`evidence/internal/plan-lifecycle.md:10`), fde went through 23 revisions, and
mac-bootstrap had 16 release pins in 5 days. If a program's typical total exceeds 3 times the measured research time
for its project type, the contract page shows both figures, and you sign an explicit override. Lite at about 6.5 days
sits just over that line for 2-day projects. The method spends more before the claim to spend almost nothing after it.

### 6.4 Where extra budget goes, in order

1. **The front end:** more census methods, more contact cells, production-scale rigs, a prototype in front of you. It
   is the only lever that shrinks both the desk and the invisible residual.
2. **Width:** more reviewers per round, only once false alarms per reviewer are measured.
3. **Depth:** more quiet rounds required to stop.
4. **Seeds**, which tighten only the statement.

The one extra round set you may buy is **capped at one per program**. It is quoted as the change it makes to the
printed bound, never as a yield. Once every carried seed is caught, that change is zero, and the quote says in words:
"no further desk review can lower this; only contact or building can". The budget is then redirected to build wave 1
as the next research instrument. The quote never shows a positive yield for a purchase that cannot move the bound
(Appendix B, break 16).

### 6.5 Every loop, with its cap

| Loop | Cap | After the cap |
|---|---|---|
| A refuted premise re-plans its decisions | Each decision reopened by refutation at most twice | Carried as a set, or class B with the best surviving option as default |
| Decision research | The intake timebox; reversible rows get at most 2 runs | Class B (default: recommended) or class C carried, with a due-date conversion |
| Frame expansion after rulings | 2 levels below the signed top-level decisions, each level timeboxed | Deeper sub-decisions carried as a set or declared build-wave residuals |
| Frame critique | Exactly 2 rounds | None |
| Census reviewer | Once per population | Later misses are measured by the certification census lens |
| Your reaction checkpoint | Once, before the freeze; taste gates at most 2 rounds against a frozen reference set | A next-version change with a price |
| Front-end return when round 1 shows far more holes than expected | Once per area, timeboxed | None |
| Certification rounds | The lower of forecast p90 + 4 and the profile's hard cap; the cap round never edits | Certifies with named known rows |
| Consistency read after fixes | One per fix cycle; its finds feed the next round | None |
| Fresh whole read before the freeze | Once | Finds fixed before the freeze |
| Dead or voided reviewer slot in a live lane | 2 re-runs | Another live vendor, "reduced diversity" printed |
| Dead vendor lane (preflight failed, or all its slots dead after re-runs) | One pause on an operator step, a class-B packet with a 48-hour default | Runs on two live vendors with "degraded: two vendors" printed; with fewer, the program stays paused |
| Seed realism rewrite | Once | Realism flag printed |
| Past-escape detector for a weak class | 1 attempt | "Weak lens" named |
| Rating re-pass when agreement is low | Once | "Adjudication unstable" printed |
| Disputed finding | 1 reproduction probe | Material-disputed, named |
| Divergence rebuild of a unit | Once per program | Unit certified at the cap, rewrite named |
| Rehearsal and relay test | Once; 1 repair and 1 re-test for the relay | "Relay unstable" printed |
| Router recall below its threshold (gate row 15) | 1 repair and 1 re-test | Gate row 15 fails, and no certificate issues until the router is fixed as tooling (§8, item 5), not as research on the program. **Edited 2026-10-08 (§9):** a row-15 FAIL at the gate is final for the items it read; the next attempt waits for fresh items, and the same items are never re-read |
| Stage overrun | At 1.5 × budget, one class-B packet whose default "proceed" fires after 24 hours | Open rows become dated carried rows with defaults |
| Escape after the gate | 2 delta rounds per escape | Counted against the forecast |
| Frame-delta cycle for omissions found during certification | Once per program: its timebox and 2 delta rounds | The omission stays a printed known row gating its dependent build waves |
| Take-back re-certification | Once per area per program | Later breaches fixed locally and recorded |
| Drift re-validation | Once per premise per program; once per certification unit | Carried row |
| Change batches into the current version | 1 per stage | Parked in the next version |
| Agent-originated change requests | 2 per program | Build-wave items with class-B defaults |
| Extra round set or profile raise | 1 per program, operator-only | Budget redirected to build wave 1 |
| Build-start revalidation | Once | None |

Nothing else loops. There is no open-ended "find gaps" loop anywhere after the frame critique.

### 6.6 Calibration: honest about what is not yet measured

- Every certificate prints "uncalibrated" together with the observed hold rate and its 95% lower bound. If every
  program holds, that lower bound is 22% at 2 programs, 74% at 10, 90.5% at 30 and 95% at 59
  (`evidence/adversary/llm/lottery.out:21-27`). At one program at a time, 30 programs is about 1.2–1.7 years.
- The calibration run replays the method on **at least 10** historical plans with known later holes before any
  certificate drops "uncalibrated". Those plans are **held out**: the checklist and the escape library are rebuilt
  without their holes first, because 25 of the 200 ledger holes are VoiceInk holes and 8 checklist rows cite them
  (Appendix B, break 13). For each known later hole, the run records whether its evidence was inside the reviewers'
  bundle before scoring recall.
- It measures false alarms per reviewer-read, the fix-born rate (new material holes per applied fix), the holes present
  at freeze (those the replayed certification finds plus the known later holes), the rater downgrade share,
  cross-vendor correlation, the invisible share
  (from non-AI detectors: contact probes and 30-day build-escape reports), quota per run,
  the re-ask router's recall on held-out phrasings (gate row 15; its `other` floor is scored on the relay decision
  since 2026-10-06, decision `1f3b8f2d01b7`, §9), whether `--setting-sources
  local` holds on the current binary, and whether the OpenAI and Google CLIs sustain the load (6 reviewers a round
  each for the full profile). It then re-runs the §3.12 model at the measured values, for the composition with Opus in
  the frontier slots (§3.8), and for two vendors after a dead-lane default (§3.8).
- Within each program, held-out seed cohorts give internal checks long before cross-program data exists.

---

## 7. What no upfront method can eliminate, and how this method bounds it

| Residual | Why it cannot be zero | What the method does |
|---|---|---|
| **Literal zero unknowns** | Certifying no hole left needs examining at least 95% of every place one could be. At 60 holes found, a 5% statement needs 3,654 seeds, all caught (`evidence/design/stopping_model.out:12`) | Replaced by the signed-frame definition and a printed forecast. The contract page states the strongest statement any spend can buy |
| **Desk-detectable holes that survive review** | Reviewers share blind spots and misrate some findings. The model leaves 0.7–1.6 per program at a strong front end (§3.12). Updated 2026-10-04 (v1.2): that range is the model at assumed inputs. At measured inputs and 20 holes at freeze it leaves 6.5–7.6 counting only calls history proved false, and 9.4–21.4 counting every false material call, rising with the reviewer count (research-calibration REPORT §5) | Printed bound, counted, fixed locally with 2 delta rounds at most. The forecast is exceeded in about 1–4% of programs in the model |
| **Holes every reviewer family misses** | Not estimable from overlap (Link 2003). About 0.5–1.1 at a strong front end, 3.3 or more at a weak one, with the share unmeasured | Contact before the claim (Stages 3 and 5). A separate forecast labeled "share assumed". A replay test puts them in their own bucket. The share is measured across programs from non-AI detectors |
| **Production, tenants, elapsed time, your eye** | The property lives only there: 6 of 200 holes | Residual rows with an owner, a date, a check and a falsifier. Carried sets where a choice depends on them |
| **New requirements and ideas** | Your intent changes: 6 of 200 holes, and 1.6 new ideas per active session-day | Parked in the next version with a price, processed at fixed checkpoints |
| **The world moves** | 4 of 200 holes were unforeseeable. Upstream release odds are 0.35–0.74 per program | Pinned snapshot, scheduled re-checks, as-of dates, market refresh, a drift counter |
| **A new model sees what the old ones could not** | 4 model releases in 58 days | Detectors pinned for the program. New-model finds go to their own ledger, counted against the invisible forecast |
| **The answerer changes** | Rules, memory and the default model change weekly | Fingerprint on the certificate. Relay-only under a different set. A scheduled rule-drift job |
| **Rating mistakes** | Material versus refinement is a judgment. One bucket in your transcripts moved from 13 to 5 when its definition changed (`evidence/taxonomy.md:285`) | Three vendors, 100% review of refinement calls, seeds through the same raters, downgrade share printed. A deferred item that proves material is an escape |
| **Estimator calibration** | Correlations and seed realism are unmeasured | "Uncalibrated" with the observed lower bound. At least 10 held-out historical programs before dropping it |
| **Reviewer isolation** | Same-user OpenAI and Google processes can read the real repo | Sanitized bundle, encrypted seeds, fresh paths, integrity grep. This is detection, not prevention, and the certificate says so |
| **The method's own machinery** | New code can hold holes of its own | Every gate row and estimator has a planted-input test that must fail. The pilot runs the hand-run kit first. The re-ask router can misread a re-ask as work; its errors fail closed, and gate row 15 measures its recall on held-out phrasings |
| **Your acceptance** | The definition is a value judgment | Precondition of the intake sitting; without it, no no-take-backs claim |

---

## 8. Build list for this environment

Build in two waves. Wave 1 must land **before** the first program, because without it the first program would run with
no re-ask protection and no tooling for its stages. Wave 2 runs **in parallel with** the pilot program, not before it.

| # | Item | Kind | Why |
|---|---|---|---|
| 1 | This directory, with its evidence | Data | `/tmp` is wiped on reboot, and it was wiped once today. Receipts must survive |
| 2 | Zero-allowed wording in `agents/deep-research.md:187`, `agents/research-decomposition-critic.md:37, 80` and `skills/research-subagents/SKILL.md:353, 798, 823`; the negative-space trigger scoped to the frame critique | Prompt edits | A prompt with a quota can never return "nothing", so a quiet-round stop is unreachable (`evidence/internal/stop-rule-machinery.md:7`) |
| 3 | The standing-rule exemption (§3.1, ruling 2) applied to `CLAUDE.global.md:464-465, 617, 619, 655, 969`, `CLAUDE.global.slim.md:248, 249, 259, 272, 364` and `hooks/completion-assert.sh:1284`, keyed on a DoD marker, plus both live copies: `~/.claude/CLAUDE.md`, and `~/.claude/CLAUDE.slim.md`, which the four account config directories link to as their `CLAUDE.md` | Rule and hook edits | Today these rules make "no, one more thing" the only compliant answer, before and after a certificate |
| 4 | Operator-only signing library: `bin/cc-signoff`'s three protections (refuse a claude ancestor, pin content, render agent-written rows as void) factored out, plus a research namespace. Used for frame and certificate signoff, the extra round set, reopen, and vetoes of overrun or below-profile defaults | Script | `bin/cc-decide` has no agent guard (`grep -ciE 'ancestr\|operator-only\|ppid' bin/cc-decide` → 0), so today an agent can buy more research for itself |
| 5 | Re-ask router: a UserPromptSubmit branch in `hooks/research-precognition-nudge.sh`, resolving program state from the program registry (item 7) by working directory, DoD, a program's name or alias in the prompt, or the single active program, plus the classifier, which fails closed on errors, timeouts and mixed labels, with its model, time limit and fallback in §4.1 | Hook | Wording-based detection misses half the gap-seeking asks. State-based routing reads every prompt, and gate row 15 measures how many re-asks its classifier misses |
| 6 | Research block: a PreToolUse deny of Agent, Workflow, `handoff-fire.sh`, vendor CLIs and the buying and reopening verbs on every turn of a certified program's session, as the program registry (item 7) shows it, unless the prompt is positively labeled a work order or a new idea, or you ran a reopen; in completeness or pushback turns, a deny of every tool except the certificate read; and a Stop-check arm in `hooks/completion-assert.sh` that blocks any reply naming an item, location or row not on the certificate, with hand-reviewed "yes, plus one more item" replies as must-block fixtures. The denies are registered by a settings migration you run, because it edits all five `settings.json` files (`~/.claude` and the four account config directories): one new PreToolUse entry that matches every tool, Workflow included (no entry matches Workflow or every tool today, `~/.claude/settings.json:726-854`), and the router's longer timeout (§4.1) | Hook, plus an operator-run settings migration | A Stop check cannot see tool calls, and 15.7% of asks spawn research inside the turn. A check that polices only a "no" would miss replies like the 20 of 73 "yes" replies that also named a new item. An unregistered deny never runs, so the pilot does not start until the migration is applied |
| 7 | Hand-run kit of seven scripts over plain record files, laid out and shaped as in `evidence/design/SYNTHESIS.md:932-1097` (profile names and caps from this report): `probe-run.sh`, including `doctor` (interactive-shell PATH, interpreters, vendor-CLI logins, credential expiry); `courier.sh` (one reviewer, rater or verifier per vendor CLI by absolute path, model id pinned and the responding id recorded, inside the §3.8 bundle it builds, with the post-round integrity grep; it also runs the vendor preflight of §3.2, step 6); `round.sh` (one frame-critique or certification round: a fresh bundle, every slot in parallel, raw outputs kept); `estimate.py` (a port of the corrected model, with seeds through raters and the invisible part priced); `seed.py` (with omission operators and an encrypted vault, its key in the keychain); `gate.sh` (the §3.10 rows, including the trace, reconcile, lint and freeze checks, the §3.5 conviction rule computed from the stored tallies, and `--render` for the certificate's state lines); `research-index.py` (writes `docs/research/INDEX.jsonl`: topic, path, date, status). `gate.sh` is also the only writer of the program registry, `~/.claude/autonomy/research/programs.json` (program, its name and aliases, repo and worktree, DoD marker, status, certificate path): the intake script registers the program through it, and a passing gate sets it to certified | Scripts and data | Lets every pilot stage run before the full tool exists (stage table below). The router (item 5) and the block (item 6) read the registry, so it ships in wave 1 |
| 8 | `research-program` skill and `/research-program` command: the intake script (both rulings, the contract page, and the program's registration through `gate.sh`, item 7), the checklist, the rubric, and the reviewer, rater, seed-author and verifier briefs | Skill, command, templates | One place that carries the protocol, so a session does not reinvent it |
| 9 | `bin/cc-research` core, absorbing the kit's scripts and record formats: index, frame, census, premise, source, decision, trace, reconcile, lint, freeze, estimate, forecast, gate, verdict (plain state lines plus the operator block), concern, park, reopen, budget and ceiling, with all caps enforced in code and append-only records | Command-line tool | The records and the gate must be computed, never re-judged |
| 10 | Probe runner, environment doctor (interactive-shell PATH) and harness self-test as `cc-research` verbs, replacing the kit's `probe-run.sh` | Command-line tool | Evidence levels are computed from probes, and tools hidden by the agent's PATH are not read as absent |
| 11 | Certification machinery: the kit's couriers, bundle builder, seed vault and round runner rebuilt as round, frame-critique and rehearsal Workflows, with the raters and the responding-model check enforced in code | Scripts and Workflows | Blind, vendor-diverse review whose isolation is enforced, not instructed |
| 12 | Scheduled launchd jobs: freshness re-checks, daily concern triage, rule drift, market refresh, each tested under `/bin/bash` 3.2.57 | Jobs | Re-checks must never run because a question was asked |
| 13 | Close integration: a `GOAL` field in `scripts/wrap-ledger.sh`, and a missing DoD reads "unknown" instead of ✅ (`:2286-2288`); a Goal line in `commands/are-we-done.md`; `--requires-gate <program>` in `scripts/handoff-fire.sh`; pending concerns and the priced menu in `hooks/operator-readout.sh` | Hook and script edits | Two separate verdicts at every close: the session's state and the program's |
| 14 | Calibration run: at least 10 held-out historical plans, with the checklist and escape library rebuilt without their holes | Study | Replaces model guesses with measured false alarms, fix-born rate, holes at freeze, downgrade share, correlation, invisible share, the re-ask router's recall and quota cost |
| 15 | Calibration log (`docs/research/research-calibration.jsonl`), plus reference-class timing per project type. The program registry, with each program's name and aliases, ships in wave 1 (item 7) | Data | The overrun factor and the "uncalibrated" label shrink only as programs accumulate |

**Order.** Items 1–8, including item 6's settings migration, which you run → the pilot (the next real greenfield, lite
profile, hand-run kit, escapes tracked for 30 days after build start) in parallel with items 9–15. Calibration results
change named sections only (the profile table, the caps, the seed counts), as priced edits. They never trigger a
rewrite of the method.

**Pilot coverage by stage.** Every stage has a wave-1 tool or a stated hand step, so the pilot never waits on wave 2.

| Stage | Wave-1 tool | Done by hand in the pilot | Replaced in wave 2 by |
|---|---|---|---|
| 1. Intake and frame | `research-index.py` before mining; the intake script (item 8) writes the frame and registers the program; `gate.sh` lints the frame; `courier.sh` runs the vendor preflight and `round.sh` the 2 frame-critique rounds; the signing tool (item 4) | The mining fan-out and the interview | Item 9 (`index`, `frame`) |
| 2. Censuses, premises, sources | `probe-run.sh` records each census, premise and source command; `courier.sh` runs the census reviewer | The second census method, by a different agent, and the grids | Item 9 (`census`, `premise`, `source`) |
| 3. Contact | `probe-run.sh doctor`, then each probe with its negative control | The scheduler-started launchd run under `/bin/bash` 3.2.57 | Item 10 |
| 4. Decisions | Decision records with their evidence tallies, checked by `gate.sh`, which derives each conviction by the §3.5 rule; packets through the existing `cc-decide` | The lead writes each tally, never a conviction, and runs the frame expansion after each level of rulings (§3.5) | Item 9 (`decision`) |
| 5. Acceptance and skeleton | `probe-run.sh` runs each acceptance row over its known-bad and known-good fixtures | The contact skeleton as build wave 0; your reaction checkpoint | Item 10 (harness self-test) |
| 6. Synthesis and freeze | `gate.sh` trace, reconcile, lint and freeze checks | The integrator, the one fresh whole read, and the sibling advisory lock | Item 9 (`trace`, `reconcile`, `lint`, `freeze`) |
| 7. Certification | `seed.py`; `round.sh` through `courier.sh` for all three vendors; `estimate.py` for the stop rule and forecast | Verifier and raters launched through `courier.sh` with the item 8 briefs; the rehearsal and relay test | Item 11 |
| 8. Gate and certificate | `gate.sh` prints every row, renders the state lines the router relays, and sets the registry to certified; the signing tool signs | Freshness re-checks within 24 hours of the gate; daily concern triage; checking the gate before firing each build wave | Items 9, 12 and 13 |

---

## 9. Open decisions for you

**Ruled 2026-10-01:** all nine adopted as recommended (decision packet `83adb541ea19`, actioned). The build that
puts them into effect is tracked in `docs/plans/RESEARCH_PROGRAM_BUILD.md`.

Each is a value call that more research cannot settle. The evidence is on disk, and the conviction is in the course
recommended.

| # | Decision | Recommendation | Conviction |
|---|---|---|---|
| 1 | Accept the definition of complete in §3.1 (100.00% of a signed frame plus a printed forecast of after-signoff changes) in place of the literal "zero unknowns" reading, and sign that the listed post-certificate activities are not research redo | Adopt | 88% |
| 2 | Exempt active programs from the standing rules listed in §3.1 (ruling 2), in both instruction variants, from intake through build | Adopt | 85% |
| 3 | After the frame is signed, park new ideas in the next version by default, with at most one accepted change batch per stage | Adopt | 85% |
| 4 | Default to the lite profile for case-sized work and standard for medium, and use full only after the calibration run measures false alarms. This replaces the earlier "widest tier" recommendation | Adopt | 75% (settled by the calibration run). Calibration 2026-10-01: 92% for lite as the default and full kept off, whose precondition failed 22–113 times over; standard for medium is not supported at measured inputs (6.5 desk holes left against lite's 6.7 at twice the reads), so lite for every size until triage brings false material findings near 0.02 per read (`docs/research/research-calibration/REPORT.md` §1, §5) |
| 5 | The escape-cost answer must be a finite number. Start at 3 research days per decision-changing escape. "Infinite" means the program does not start | Adopt | 80% |
| 6 | Suspend "upgrade immediately" for reviewer model binaries while a program is in certification | Adopt | 85% |
| 7 | Convert a class-C gate to a class-B default of its reversible option at its due date, descoping its dependent waves instead of waiting | Adopt | 78% |
| 8 | Freeze this method as version 1 with no further critique rounds. Run the pilot in parallel with the tooling. Change only named sections, from measured results | Adopt | 85% |
| 9 | Run program sessions on one instruction variant (both variants carry the exemption), and record its hash on the certificate | Adopt | 80% |

**Ruled 2026-10-04** (two decision packets, actioned in session d8964eb2; the 2026-10-01 rulings above stand except
where named here):

- **`1bf69e5c1775`: method v1.2 is adopted.** It overrides ruling 8's freeze for these four changes only, each from
  `docs/research/upfront-method-audit-2026-10-04/REPORT.md` §3: (a) measure triage precision, then fix it (audit row
  1); (b) certify the built and tested result before "done" (row 2); (c) stop contact and build-to-learn on yield
  instead of a calendar box (row 7); (d) re-sign the pilot contract on the measured forecast (row 3). No v1.2 change
  edits this report or the kit yet: each lands as a named, priced edit after the triage precision measurement
  (`docs/research/triage-precision-study-2026-10-04/`), and ruling 8's rule (change only named sections, from measured
  results) governs how. The build is wave E of `docs/plans/RESEARCH_PROGRAM_BUILD.md`.
  Changes (b) and (c) are specified as appended sections: §11 (Stage 9, certify the built artifact; built gate
  rows 20–25; the forecast split before and after implementation signoff) and §12 (stages 3 and 5 stop on yield;
  decisions below 90 tagged by what blocks them; a priced per-decision extension; research-gate rows 18 and 19).
  Each carries its price and its assumed inputs, and applies only to a frame signed under method 1.2.
- **`4bf73c4e55d5`: the re-ask classifier's time limit is 9 s**, replacing §4.1's assumed 6 seconds, in both the
  router (`scripts/research-kit/router.py` `CLASSIFIER_TIMEOUT_S`) and gate row 15's measurement
  (`scripts/research-kit/heldout.py` `ROUTER_TIMEOUT_S`). The hook's registered timeout stays at the 10 seconds
  `migrations/0050` set. Gate row 15 is re-measured at the new limit; its reading is in wave E1 of the build plan.

**Updated 2026-10-04 (v1.2): the edits made under ruling `1bf69e5c1775`**, each named and from a measured result, as
ruling 8 requires. Earlier text is kept and each edit is marked where it sits.

- **Change (a), measurement half: triage stays as calibrated.** The triage precision study
  (`docs/research/triage-precision-study-2026-10-04/REPORT.md`) tested four candidate filters against a blind,
  three-vendor reading of the rubric. No filter beats the calibration's triage as run (provisional, 70% conviction).
  On the line closest to the operator the triage as run leaves the fewest changes after signoff: 8.86 per program in
  Lite and 8.83 in Standard (modeled), with the chance of at least one at 1.00. So §3.11, the rubric and the triage
  steps of §3.8 are unchanged. The study left one measurement open, the executable-reproduction filter applied after
  the triage as run. It was run the same day and fails the study's decision rule (that report's appendix A): on the
  operator-strict line it leaves 9.1–9.2 unannounced changes in Lite against the triage's 8.8, and in Standard the
  interval of the difference spans zero. So no filter is built, and change (a) closes with the triage as it is.
- **Change (d), code and text half: the forecast is stated from measured inputs.**
  - §1: the "1–4%" and "6–9 in 10" figures carry a dated note with the measured values.
  - §3.12: the table's first column header carries the measured holes at freeze. The table's rows are unchanged; the
    measured re-run is the calibration report's §5.
  - §7: the "0.7–1.6" desk-detectable range carries the measured range.
  - Decision 4 above: "standard for medium" is withdrawn as a default. Lite is the default for every size until the
    measured false-call rate falls; `intake.py` warns on any wider profile with the two simulated figures, and stops
    warning by itself if the measured file ever shows wider review paying.
  - `scripts/research-kit/estimate.py` reads `research-calibration/evidence/params-measured.json` by default
    (invisible share 0.121, false material calls 1.13 per reviewer-read, downgrade 0.223, omission share 0.577,
    fix-born rate 0.211), and refuses if the file cannot supply them. `--base` runs the assumed set as a contrast.
  - The contract page prints the measured forecast and the assumed one beside it as a contrast.
  - Price: no added program cost. The contract page runs 2 to 4 simulations where it ran 1, a few seconds each.
- **Change (d), operator half:** the pilot's contract is re-rendered on the measured forecast as a draft beside the
  signed page, and the re-sign is filed as one operator step (build plan, wave E3a and E4). The signed page and the
  pilot's records are untouched until the operator re-signs.

**Updated 2026-10-06: the edits made under decision `aba630ebe329` (part e)**, each named and from a measured result.
Earlier text is kept and each edit is marked where it sits. The measured reason is the same for all three: on the
held-out set v3 about 0.24 of ordinary prompts were relayed (35 of 148), and a relay blocks every tool for the turn
(`docs/research/reask-overflag-decision-2026-10-06/false-relay-cost.md`).

- **§4.2, no relay label on a machine-envelope turn.** A completeness or pushback label is no longer carried into a
  `<task-notification>`, `<teammate-message>` or `[handoff …]` turn. That turn runs as "anything else", with research
  tools still denied. Reason: one false relay used to block every tool of every background agent in the session until
  the operator typed again, so its cost was not one turn.
- **§4.2, the one-word override.** `misrouted`, typed as the next prompt after a relay turn, relabels that turn
  "anything else", once. Research tools stay denied and it never becomes a work order. Every relay turn shows a
  one-line notice naming the word. Reason: about 1 in 4 ordinary prompts was relayed, and the operator had no way to
  get that turn back.
- **§4.1, overridden relays are counted.** Each override is counted in the `operator-readout` block, beside the
  "classifier unavailable" count. Reason: the count shows how often a relay was wrong in real use, which the held-out
  set only estimates.

Gate row 15's thresholds are unchanged. These edits lower the cost of a false relay, not its rate.

**Updated 2026-10-06: the edit made under decision `1f3b8f2d01b7`** (the operator's reply "flag-decision-90"), named
and from a measured result, as ruling 8 requires. Earlier text is kept and the edit is marked where it sits (gate row
15, §6.6).

- **Gate row 15, the `other` floor is scored on the relay decision.** An agreed `other` item is right when the router
  relays it (completeness or pushback) exactly when the raters' agreed label relays; a fallback is a miss, as in every
  stratum. The floor stays 0.90, and every other row-15 threshold and the 9 s limit are unchanged. The exact-label
  rate is still printed and never fails the row. Reason: on the 240 agreed `other` tuning prompts of wave E1h no
  configuration reached the exact label above 0.86, and about 0.87 is the ceiling from confusing the five labels that
  do not relay, which the router treats alike; the raters themselves agreed on the exact label of 240 of 407. On the
  relay decision the adopted fast-plus-careful pair (Sonnet 5.5 thinking off, then haiku thinking on, union join)
  reads 229 of 240 = 0.95 (205 of the 216 non-relay ones left unflagged, all 24 re-asks relayed), the live router
  223 of 240 = 0.93 (`docs/research/router-classifier-e1h-2026-10-06/`; build plan wave E1i). A wrong relay now costs
  one word (`misrouted`, §4.2).
- **§4.1, the fast call runs `sonnet_latest`** (ruling part (a) of decision `aba630ebe329`, which allowed this edit
  only if a non-`haiku_latest` configuration was adopted; `1f3b8f2d01b7` adopted one). Reason: on wave E1h's tuning
  base Sonnet 5.5 thinking off as the fast call cut agreed non-relay prompts wrongly relayed from 57 of 504 to 36
  under the union join, with pooled recall unchanged at 0.99. The careful call stays on `haiku_latest`, whose
  model (`claude-haiku-4-5`) has a retirement floor of 2026-10-15; whatever `haiku_latest` moves to is a new
  configuration that gate row 15 has not measured.

**Updated 2026-10-08: the edits made under the row-15 rulings** `a7fd5e2ee7c8`, `915d7fb98b7f` and `17aff7158fa6`
(the operator's reply "all recommendations"; `docs/research/reask-row15-rulings-final-2026-10-08/REPORT.md`), each
named and from a measured result, as ruling 8 requires. Earlier text is kept and each edit is marked where it sits
(gate row 15 in §3.10, and the gate-row-15 row of §6.5's cap table). Row 15's thresholds, the 9 s limit and the
classifier configuration are unchanged. Built in wave E1l of `docs/plans/RESEARCH_PROGRAM_BUILD.md`.

- **Gate row 15, the load bound is a stated condition** (`17aff7158fa6`). Before the read is logged the gate waits
  for 1-minute load 40 or below, under a start cap; if the cap expires it refuses and logs no read. After that each
  item waits for the same bound, under one long, finite total cap for the read; past it the row prints "read spent,
  no verdict". Each routed item records its load. The certificate states the bound as a condition of row 15 and
  prints beside it RULE E1k's real-load figures above load 150 (hedge-on fallback rate, rows held with one call
  silent), and the read waits until those figures are on record with a pass. The gate is launched detached, so a
  tool timeout or the job reaper cannot cut the read. Reason: every miss of the 2026-10-07 read was a 9 s timeout,
  and a 73-minute read started at a random minute overlaps load 150 or more 21.9% of the time; only about a third of
  live prompts arrive at load 40 or below, which is why the real-load figures stand beside the bound.
- **Gate row 15, a FAIL at the gate is final for those items** (`a7fd5e2ee7c8`, guard 3). The next attempt waits for
  fresh items, and the same items are never re-read. Reason: sample noise alone gives row 15 a 22-72% chance of
  failing per read, so reading the same items until they pass would be a real risk; the cap in §6.5 limits repairs,
  not reads.
- **Gate row 15, the third-read rule** (`915d7fb98b7f` item 5, `a7fd5e2ee7c8` guard 4). A stratum of a held-out set
  is read at most twice. Each further read needs its own operator signature
  (`cc-signoff research:<slug>/third-read/<set>.<stratum>`) and is printed as a disclosed cost; without one the gate
  refuses before it opens the set. Reason: the scorer used to note earlier reads without refusing them, so a gate
  run with the old map would have spent a third read of v3 silently.
- **Gate row 15, the read guards** (`a7fd5e2ee7c8`, guard 1). The row decrypts and logs a read only with the
  operator's read consent for that run (`gate.sh run --consent-sealed-read`), only when the router is a real command
  and not its kill switch `off`, and only after every other row passed in the same run; otherwise it fails without
  reading. Reason: a session launched with the kill switch would have run `/bin/bash -c off` on every item and still
  spent the read.

---

## Appendix A. Every hole class: mechanism, gate row, declared residual

| Class | Mechanism in this method | Gate row | Declared residual |
|---|---|---|---|
| Claim frame narrower than the question (23) | Two verdicts at every close; certificate lines over your question frames; computed reconciliation; re-asks answered from records; "already recorded" triage | 1, 12, 15; §4 | None expected |
| Operator intent after the claim (12: 6 new, 6 never asked) | Mining plus a 12-question pre-filled interview; your reaction checkpoint; parked next version; unasked-intent counter | 1 | New requirements (6 of 200), parked and priced |
| Unverified premise (29) | Premise records with computed evidence levels; highest-value probes first; refutation-rate check; conviction from a tally by a fixed rule (§3.5) | 4, 5, 10 | Secondary premises where probing has no value, stated |
| Population never enumerated (32) | 33-row checklist; two-method censuses; frame expansion after each level of rulings; hazard and state grids; source list; census reviewer once; frame critique on rows; omission seeds | 1, 2, 3 | Members no search reaches, inside the printed bound |
| Instrument could not fail (29) | Harness self-test red then green; red proof per row; negative controls; 5+ samples with a load control; re-execution, never recall | 6, 7 | Stub-validated rows labeled build-validated |
| Research lost (12) | Research index written at intake (`research-index.py`, §8 item 7); trace check over findings, headings and claim sentences; research prose in the reviewer bundle; persistence in the repo, with private receipts held by content hash; one topic owner | 8 | None expected |
| Self-created by edits (10) | Single integrator; material-only fixes; one consistency read per fix cycle; shadow seeds; fix-born rate and the divergence rule; verification-only cap round | 9 | Fix-born holes inside the shadow cohort's bound |
| Review late or unsaturated (8) | Certification before any claim; a vendor preflight at intake; dead slots re-run, and no round counted while a vendor lane is dead; build gated on the certificate | 13; `--requires-gate` | None |
| Contact-only (30) | Contact wave before design; skeleton as build wave 0; seven contact cells; every handed command run; carried sets | 5, 7, 11 | Production, tenant or time (6 of 30), owned and dated |
| Reality moved (8) | Pinned snapshot; scheduled re-checks; as-of dates; one build-start revalidation; non-mutating probes | 10 | Unforeseeable drift (4 of 8), counted as drift |
| Criterion never operationalized (7) | Superlative lint; measured ceilings; thresholds with a negative branch; reference sets with dated gates; hold expiries | 1, 6 | Taste verdicts are yours, as dated gates capped at 2 rounds |

---

## Appendix B. Every adversarial break, and how it is resolved

"Resolved" means the method now contains the fix. "Residual" means the fix bounds the break, and the remainder is
declared in §7.

| # | Severity | Break (short) | Resolution |
|---|---|---|---|
| 1 | Fatal | Agents file challenges on every ask, recreating "one more thing" as a sanctioned sentence | Concerns only from executed detectors or an operator prompt with a location; blocked in completeness turns; pending never shown; daily batch (§4.4). Resolved |
| 2 | Fatal | Resident rules (the slim close-question rule, the read-only-turn rule, the Stop hook's drive check) outrank a one-paragraph injection; tool calls are invisible to a Stop check | PreToolUse block that denies research tools unless a prompt is positively labeled as work, and every tool but the certificate read in completeness and pushback turns (§4.2); a Stop check that blocks a reply adding any item not on the certificate, after a "yes" as much as a "no" (§4.4); the exemption ruled before the first program (§3.1) and shipped in wave 1 (§8, items 3, 5, 6); plain state lines with no verbs; menu only in your block. Resolved |
| 3 | Fatal | Extra rounds, raises and vetoes route through `cc-decide`, which has no agent guard | Operator-only signing library for all of them; caps in code; 1 purchase per program (§6.4, §8 item 4). Resolved |
| 4 | Fatal | The invisible part is outside the bound, so its arrival reads as a take-back | Separate invisible forecast labeled "share assumed"; replay test assigns the bucket; omission seeds; frontier-model slots counted as Opus; share measured from non-AI detectors (§3.9, §3.12, §5.3, §6.6). Residual (§7) |
| 5 | Fatal | Same-family raters downgrade real holes near the stop while seeds bypass them | Seeds through the same raters; non-Anthropic rater 1; 100% review of refinement calls; raters blind to round and streak; downgrade share printed; deferred-then-material counts as an escape (§3.8). Residual (§7, rating mistakes) |
| 6 | Major | Conviction noise and ±20% estimate moves count as material | Conviction triggers deleted; option flips need a reproduced consequence; only measured figures, as intervals; conviction computed from a tally by a fixed rule, with required levels for document and reasoning claims (§3.4, §3.5, §3.11). Resolved |
| 7 | Major | Width multiplies false alarms; the cap round edits after the freeze | False alarms modeled per reviewer; profile re-derived (§3.12); full only after measurement; verification-only cap round; fresh read capped (§3.7, §3.8). Resolved |
| 8 | Major | A post-freeze frontier sweep breaches the bound and re-certification has no cap | Frontier derivation moved to the frame critique; after the freeze only in its fixed reviewer slots, in every round or in none; take-back re-certification once per area (§3.2 step 6, §3.8, §5.3). Resolved |
| 9 | Major | Paraphrased re-asks and "Are you sure?" bypass the regex; the rehearsal never tests the real wording | State-based routing with a classifier that fails closed on errors, timeouts and mixed labels, and that resolves a program named from any pane (§4.1); research tools denied unless a prompt is positively labeled as work (§4.2); the router's recall on held-out phrasings checked as gate row 15 (§3.10); relay test with your literal phrasings, 20 trials, at least one from outside the program's directory (§3.8). Residual (§7, the method's own machinery) |
| 10 | Major | The answering model, rules and memory change after certification | Fingerprint; relay-only under a different set; scheduled rule-drift job; one instruction variant (§4.4, §5.5, decision 9). Residual (§7) |
| 11 | Major | Reviewers cannot see research prose or house rules, so "research lost" holes are invisible | Bundle includes research prose, evidence and a house-rule digest; seeds anchored on research-prose findings; trace check over headings and claim sentences (§3.7, §3.8, §3.9). Resolved |
| 12 | Major | The triager picks the bucket and only "escape" costs | "Material changes, any cause" counter with its forecast; take-back on the total and per area; fixed class-to-area table; blind bucket rater; agent change requests capped at 2 (§5.2, §5.3). Resolved |
| 13 | Major | The calibration backtest is in-sample, and 2 programs prove little | Held-out plans with the checklist and library rebuilt; 10 or more before dropping "uncalibrated"; observed lower bound printed (§6.6). Residual (§7) |
| 14 | Fatal | The anti-loop rules depend on a ruling your recorded words contradict, left as one more open packet | Both rulings are preconditions of the intake sitting, shown with your 09-14 and 09-27 quotes; decline means no program; post-certificate activities signed as not research (§3.1). Resolved |
| 15 | Fatal | Your new ideas become uncapped change requests; "No — change open" is a sanctioned answer | Parked next version; "blocks this version" only with a price; 1 batch per stage; running rounds untouched; a "no" cannot cite parked ideas; parked count on line 1; a reopen verb (§5.1). Resolved |
| 16 | Fatal | Unlimited budget plus an extra-rounds quote that always shows positive yield | Quote is the change to the bound (zero once seeds are caught), stated in words; 1 purchase per program; a finite escape cost required; the illustrated certificate uses the corrected model (§3.2, §4.3, §6.4). Resolved |
| 17 | Major | Scope reopens through questions that are not completeness asks, or orders bundled into them | Every prompt in a program routed by state; a prompt with mixed labels treated as a completeness question; research orders go to priced options; a reopen verb (§4.1, §5.1). Resolved |
| 18 | Major | Outside populations grow weekly, so "best in the world" never closes | As-of dates and admission rules; market refresh after ship; "best available as of <date>" wording; checklist row 33 (§3.2, §3.3, §5.5). Resolved |
| 19 | Major | Re-checks on every ask and a 72-hour expiry flip certificates; drift re-validation has no cap | Scheduled re-checks only; stale only on a verdict flip; one re-validation per premise; pinned snapshot with a sibling lock; build-start scope limited to wave-1 paths (§3.7, §3.10, §5.5). Resolved |
| 20 | Major | A new model finds declared-invisible holes and they count as take-backs | Detectors pinned per program; responding model checked; the upgrade rule suspended for reviewers during certification; new-detector ledger against the invisible forecast (§3.8, §5.2). Residual (§7) |
| 21 | Major | Your late items are labeled at the triager's discretion and stay uncounted | One row per class; a deterministic rule (intake question asked and answered → new requirement, otherwise frame defect); counters on line 1; your one-line ruling on disputes (§5.2). Resolved |
| 22 | Major | Before any certificate, resident rules still drive refinements into the plan during certification | The exemption applies from intake through build, keyed on the DoD marker; wave-1 tests show a round session filing, not integrating, a planted refinement (§3.1, §8 item 3). Resolved |
| 23 | Major | Taste criteria appear only after you see an artifact; taste gates have no cap | Reaction checkpoint before the freeze and a frame re-sign; 2 rounds of your eye against a frozen reference set; a third round is a next-version change (§3.6). Resolved |
| 24 | Minor | Class-B defaults below 90% look closed, then the below-90 rule reopens them | Shown as "decided by default at N%"; no class-B default on irreversible decisions; the timebox receipt satisfies the rule (§3.1, §3.5). Resolved |
| 25 | Fatal | Declared invisible holes surfacing at build are booked as escapes against the small desk bound | Replay test; separate invisible forecast; any-cause chance printed; re-certification once per area; undeclared contact holes get their own row (§3.12, §5.2, §5.3). Residual (§7) |
| 26 | Fatal | Your conviction-plus-research prompts reopen rows the method leaves below 90% | Timebox receipt satisfies the below-90 rule; row lines show conviction, receipt and the contact event that would move it; research orders routed to priced options (§3.1, §4.1). Resolved |
| 27 | Fatal | Unenumerated-population misses land as uncounted frame defects with uncapped mini-programs | Frame defect only when no checklist row covers the axis; source tie-breaker dropped; counters shown and logged; agent change requests capped at 2 (§5.2, §5.3). Resolved |
| 28 | Major | The timeline is 7–14 times the measured research time | Size-scaled profiles with lite as the default; release odds and your waits in the ceiling; skeleton as build wave 0; the 3× check with a signed override (§6). Residual (lite is still about 3 times a 2-day project) |
| 29 | Major | Stopping at the cap edits after the freeze, contradicting the freeze row | Verification-only cap round; the certified snapshot is the last one examined; named known rows; tighter materiality (§3.8, §3.10 row 9). Resolved |
| 30 | Major | Carried rows deadlock build; the probe list is unbounded; the credential check is circular; stub validation passes as sound | Carried-row states; build refused only for FAIL or unresolved class C; value-ordered probes inside the stage budget with the tail declared as build residual; "valid or renewable"; stub rows labeled (§3.6, §3.10). Resolved |
| 31 | Major | Your dormancy is outside the guarantee | Due dates and defaults on every gate; class-C conversion; frame-omission finds go to one bounded frame-delta cycle that gates only the dependent build waves; calendar ceiling and a "waiting on you since" line (§5.4, §5.6). Resolved |
| 32 | Major | Several loops sit outside the capped list | Complete loop table with caps, and the ceiling recomputed with every capped term (§6.1, §6.5). Resolved |
| 33 | Major | The bundle lacks untracked dependency source, live premises and history | Lockfile-pinned sources and a git-log digest in the bundle; live premises marked not auditable by reading and left out of the desk bound; the calibration run records whether evidence was in the bundle (§3.8, §6.6). Resolved |
| 34 | Major | In a high-churn repo, freshness never settles | Pinned snapshot; one build-start rebase and revalidation; re-check only paths that can trip a registered flip condition; drift shown as information (§3.7, §3.10, §5.5). Resolved |
| 35 | Major | The literal 100.00 stays out of reach, so the loop moves to purchases | The contract page states the strongest achievable statement; the purchase refuses below the floor and redirects to build wave 1; the definition is a precondition (§3.1, §6.4). Resolved |
| 36 | Major | Cross-program calibration takes years; "4 families" counts Anthropic twice | Within-program held-out seed cohorts; observed lower bound printed; vendors counted, not model names; frame-defect counts enter the calibration log (§3.8, §6.6). Residual (§7) |
| 37 | Major | The method is not applied to itself | Frozen now, with this review as the last critique; wave 1 first, pilot in parallel; calibration results change named sections only (status line, §8). Resolved |

---

## Appendix C. Evidence index and how to re-run

| Path under `evidence/` | What it is |
|---|---|
| `taxonomy.md`, `taxonomy_holes.py`, `taxonomy_stats.py` | The 200-hole root-cause taxonomy, its ledger (one row per hole with a receipt), and the script that re-derives every count |
| (not committed) | The 88 completeness re-asks the forensics read. They are raw operator prompts, so they stay local: `python3 ~/.cache/rescomp-rebuild/extract.py` rebuilds them |
| `forensics/shard-0.md` … `shard-7.md` | Per-case transcript forensics with quotes and receipts |
| `internal/close-assertion.md`, `stop-rule-machinery.md`, `plan-lifecycle.md`, `greenfield-cases.md`, `ca_scan.py` | Audits of how "complete" is asserted, the research machinery, plan goalpost moves, and the seven greenfield cases |
| `external/stopping-rules.md`, `unseen-estimation.md`, `llm-failure-modes.md`, `systems-engineering.md`, `epistemic-limits.md` | Literature reviews with primary citations |
| `design/SYNTHESIS.md`, `SYNTHESIS.r1-pre-reboot.md`, `statistical-stopping.md`, `frame-contract.md`, `reality-contact.md` | The three candidate designs and the synthesis this report finalizes |
| `design/cert_sim.py` and `design/*.out` | The shared model and its outputs (tier curve, stopping model, calibration, seed realism, forecast check, width) |
| `adversary/llm/*`, `adversary/reality/*`, `adversary/opscope/*` | The adversarial review's measurements (ask turns, regex recall, false alarms, invisible-share sweep, take-back simulations, idea rate, bypass scan) |
| `final/profile_sim.py`, `final/profile_sim.out` | The corrected profile model behind §3.12 and §6.1 |
| `final/verify_quotes*.py` | The scripts that re-read §2.3's quotes from the raw transcripts |

To re-run a model from this directory: `PYTHONPATH=evidence/design python3 evidence/final/profile_sim.py` (about 90
seconds), and likewise for the files under `evidence/design/` and `evidence/adversary/llm/`. The scripts look for
`/tmp/rescomp/design` first and fall back to `PYTHONPATH`. `python3 evidence/taxonomy_stats.py` re-derives the taxonomy
counts. The two bulk raw-prompt dumps the forensics started from (`prompts.jsonl`, `prompts_dedup.json`, 3.3 MB of
verbatim operator prompts) are deliberately not copied here. `evidence/internal/ca_scan.py` regenerates them from
`~/.claude*/projects/*/*.jsonl`.

---

## 10. Certification record: this report under its own stopping rule

You asked whether this report is itself 100.00/100.00 complete. It was tested the way the method tests a frozen plan:
a fixed question, a fixed materiality rule, blind reviewers using three lenses (launch readiness, correctness, coverage
of your bar), models rotated across Opus, Sonnet and Fable, zero findings explicitly allowed, and every finding put to
two independent refuters. Only findings both refuters failed to break were kept.

| Pass | Text reviewed | Raw findings | Survived both refuters | Unique | New per round (3 rounds) | Estimated still unfound |
|---|---|---|---|---|---|---|
| 1 | version 1 as landed | 50 | 30 | 18 (15 major, 3 minor) | 11, 4, 3 | about 10 |
| 2 | version 1.1, after fixing all 18 | 39 | 23 | 17 (12 major, 5 minor) | 9, 4, 4 | about 42 |

"Estimated still unfound" is the Chao1 estimate from how many reviewers found each item (most were found once).
Records: `evidence/certification/pass1-findings.json`, `pass2-findings.json`.

**What this shows.**

- **Not certified.** Neither pass reached 3 quiet rounds, so the method's own gate would not issue a certificate for
  this document.
- **The fixes made new holes.** 12 of pass 2's 17 findings sit in text that the first fix round added. That is the
  fix-born class from §2.2 (the session's own edits create the next hole), measured here on this report. More
  fix-and-review rounds on this document would repeat the loop the report diagnoses, so desk review stops at the cap.
- **What held.** No finding in either pass changed the diagnosis in §2 or the eight-stage structure in §3. All 35
  findings are specification details: the tooling (the re-ask router and classifier, registry states, build order),
  gate-row conditions, budgets and defaults, rules inside a stage (pass 1 added a vendor preflight, a frame-expansion
  step and a conviction rule), or how precisely a number is stated.
- **Where the rest closes.** These are details of software that does not exist yet. They close by building wave 1
  with a failing planted-input test for each item below, and by running the pilot, not by more reading.

**Open items, carried into wave 1 as acceptance requirements** (pass 2; pass 1's 18 are fixed in this version, with
findings 7 and 13 partly fixed and labeled as assumptions for the calibration run):

| # | Severity | Open item | Required resolution |
|---|---|---|---|
| 1 | major | The relay test (gate row 14) runs before the registry says 'certified', so the tool block it relies on is never switched on | In §3.8, §4.2 and §8 item 7, add a registry state 'certifying' that gate.sh sets at the freeze (§3.7 step 7). Key the §4.2 deny and the §4.4 Stop check on 'certifying or certified', so the 20 relay trials run with the block on. Add a wave-1 planted-input test that checks a completeness prompt denies Agent, Workflow, handoff-fire.sh and the vendor CLIs. |
| 2 | major | With one program active, close questions in every other pane get routed to its certificate and all-tool deny | In §4.1 and §8 item 5, delete the single-active fallback (key 3), so routing uses only working directory, DoD marker or the program's name or alias in the prompt. Otherwise, have the classifier label whether a question is about this program, and in fallback panes show a status line only, with no deny and no relay order. |
| 3 | major | A classifier error or timeout denies every tool (not just research tools), the label carries over to the rest of the session, and there is no breaker or kill switch | Change line 724 to say the cost is 'every tool except the certificate read, for the rest of the session'. In §4.2, treat 'classifier unavailable' as separate from a positive completeness label: deny only the research verbs, retry classification on the next genuine prompt, and never let a continuation inherit a fallback label. Label prompts that carry the --requires-gate work-order marker without calling the classifier. After N consecutive fallbacks, print 'classifier unavailable' and keep only the research-verb deny. Add an operator kill switch. |
| 4 | major | Nothing in the pilot applies fired class-B defaults or converts class-C rows at their due date, and live autonomy-sweep can dispatch fired defaults as backlog work | In §3.5, §5.6, the stage-4 pilot row and item 7, require every program packet to be filed with --project <deliverable repo> and --default-effect no-change. Add a 'gate.sh sweep' step, run by hand in the pilot and by launchd in wave 2. The sweep reads cc-decide list --all --json for expired-actioned packets and applies them to the decision records. When a class-C due date passes, it opens a class-B replacement packet and acts on the old one. |
| 5 | major | 'Forecast exceeded in 1–4%' is the rate the 95% bound is exceeded, not the rate the printed point forecast is exceeded (about 17–28%) | Resolved in §1 of this version: the 1–4% is now stated as the rate the 95% bound is exceeded. The rate the typical-case forecast is exceeded is left to the calibration run, because no saved simulation output reports it. |
| 6 | major | The 1–4% take-back rate comes from a total-only simulation, but the method also runs a take-back test per area | Option 1: make per-area bounds informational only, so §5.2 and §5.3 step 5 match profile_sim.py's two-stratum test. Option 2: add the class-to-area table and per-area seed allocation to profile_sim.py, re-run it, and reprint the exceedance rate and the after-signoff ceiling. Either way, reconcile 'once per program' (line 868) with 'once per area per program' (line 1008). |
| 7 | major | Gate row 11 has no allowed reason for residuals the method itself creates (below the depth cap, over the stage budget, stub-validated, probe tail) | Add to gate row 11 the reason classes 'depth cap (§3.5)', 'stage budget exhausted (§3.6)' and 'stub-validated (§3.6)'. Each needs an owner build wave, a due date and a dated closing probe, and is exempt from 'closest probe already run'. State that these rows render as FILED, not FAIL. Add them to §3.1's signed list and to §7. Print the count of capped rows on the certificate and the contract page, and count any that are realized in the any-cause counter. |
| 8 | major | The §4.2 research block denies the post-certificate activities the method requires (escape fixes, the frame-delta cycle, triage raters), and reopen is the only way through | Add a route to the §4.1 table and an allow condition to §4.2 for contract-listed activities. When the registry holds an open priced activity id (escape, frame-delta cycle, triage batch) opened by triage or the kit, allow round.sh --delta, courier.sh and Agent calls tagged with that id. State that these activities never go through cc-research reopen and are booked against their escape counter. |
| 9 | major | A frame-omission known row cannot close once its single frame-delta cycle is used up or the operator does not re-sign, so dependent build waves stay blocked | In §5.4 step 1, give the frame re-sign a due date and a default, like the other §5.6 gates. In §5.4 and the §6.5 loop table, define what happens after the cap: omitted rows become class-B/C rows with defaults, or their dependent waves are descoped as for class C. The known row then closes and --requires-gate stops refusing without a reopen. |
| 10 | major | The standing-rule exemption is keyed on a DoD marker that no step writes, and that key differs from the router's | Option 1: key the exemption (§3.1 ruling 2, item 3) on the same program-registry resolution that §4.1 uses (working directory or worktree from programs.json). Option 2: state in §3.2 step 9, items 8 and 13, and the Stage 1 pilot row that the intake script writes program:<slug> into the lead's DoD line and that handoff-fire.sh --requires-gate writes it into each fired session's DoD. |
| 11 | major | Gate row 15 measures only completeness recall, with no floor for correct labels on other prompts and no ceiling on fallbacks, so an always-failing or over-labeling router passes | Add two conditions to gate row 15 and fail it on either: a held-out set of work-order and other non-completeness prompts with a minimum correct-label rate, and a maximum fallback (timeout plus error) rate measured at the configured time limits. |
| 12 | major | Gate row 15's held-out pool is the 280 asks the old regex selected, so it has no regex-missed paraphrases or pushback | In gate row 15, define the held-out sampling frame in strata: regex-matched asks, regex-missed paraphrases (the regex_recall gap-seeking set and the 77 post-done prompts that did not match), and pushback phrasings. Report recall per stratum and require at least 0.95 in each. Note that the 280 asks were selected by the regex. |
| 13 | minor | No build item creates the sealed, labeled held-out set that gate row 15 requires | Add to §8 item 5 or 7: before the router is written, split the candidate prompts into a tuning set and a sealed set of at least 40, stored where the router's builder cannot read it. Have two raters label the sealed set, and have gate.sh read it at run time. |
| 14 | minor | §7's strong-front-end residual range (0.7–1.6) and §1's '6–9 in 10' leave out the default Lite profile at 20 holes | In §7, change the range to 0.7–2.7, noting that 2.7 is the default Lite profile at 20 holes. In §1, change 'about 6–9 in 10' to 'about 6–10 in 10' to match §3.12. |
| 15 | minor | '20 of 73 yes-replies named a new item (27%)' is a regex count with false positives and duplicate sessions, and the lottery numbers inherit it | Dedupe the ask census by (session uuid, timestamp): 236 asks, 61 yes-replies, 16 hits. Hand-label the 16 hits and report the true count (about 2–3). If they are not labeled yet, mark 27% as a regex upper bound. Recompute the 280, 268 and 44 counts and lottery.py's r, and the §4.4 '1.6–8.1 notices / up to 48%' figures. |
| 16 | minor | The front-end return trigger 'well above the design point' has no number | Replace 'well above' in §6.1 and the §6.5 loop table with a numeric threshold, for example round-1 forecast p50 above 1.5x the profile's design point. List it with the assumed inputs the calibration run measures. |
| 17 | minor | The ceiling is not enforced in code during the pilot, because cap enforcement (item 9) ships in wave 2 | Option 1: move cap enforcement into the wave-1 kit. round.sh refuses a round past R_max or the hard cap, and gate.sh gets a row checking rounds and stage time against their caps. Option 2: change line 947 to say the pilot's ceiling is procedural until item 9 lands. |

---

## 11. Method v1.2: Stage 9, certify the built artifact before "done"

Added 2026-10-04 under ruling `1bf69e5c1775` (§9), change (b), from audit row 2
(`docs/research/upfront-method-audit-2026-10-04/REPORT.md` §3). Nothing in §3 is deleted. Stages 1–8 certify the
plan; this stage certifies what was built from it. It applies to a program whose signed frame carries
`method_version` 1.2 or later; a frame signed under 1.1 keeps the eight-stage method.

**Why.** In the replay, 131 of 224 known holes the reviewers missed (58.5%) were later found by building, probing,
production or the operator (measured, audit §3 row 2). §6.4 already says "only contact or building can" lower the
residual. Under v1.1 those finds land after the claim. Stage 9 moves the build-findable ones in front of the
implementation signoff.

**When.** After the last build wave, before you sign the implementation. The registry gains two states:
`certified → build-certifying → build-certified → closed`. `gate.sh built-freeze` pins the built snapshot and sets
`build-certifying`; `gate.sh built-run` evaluates rows 20–25 and, when all pass, writes `built/BUILT-CERT-v<n>` and
sets `build-certified`. Both states are active for the §3.1 exemption and the §4.2 research block.

**What it reuses.** Rounds (a new round kind `built`, same reviewers, vendors, strategies and re-run caps as §3.8),
raters and the §3.11 rubric, and the seed idea of §3.9. The instruments are code-native:

1. **A failing-test repro for every finding.** A built-stage finding is admitted as material only with a test
   command that the tool itself runs and sees fail on the built snapshot. A finding with no failing test is recorded
   as `rejected-no-repro` and counted, never material. The fix is accepted when the same command passes.
2. **Mutation testing of the acceptance harness, with mutants as seeds.** Sealed mutants (one planted defect each)
   are applied to a copy of the built artifact, one at a time, and the acceptance harness runs against each copy. A
   mutant the harness fails on is killed. A survivor is a hole in the harness: it becomes a finding whose repro is
   the new harness row that kills it. The kill rate is this stage's seed catch rate.
3. **An as-built contact re-run.** Every Stage 3 and Stage 5 probe of kind skeleton, handed command, dry-run deploy
   or fault injection, and every acceptance row, runs again against the built snapshot from an empty environment: a
   fresh empty `HOME`, `PATH=/usr/bin:/bin`, and the scheduler's interpreter `/bin/bash` 3.2. The runner records the
   environment; it is never typed.
4. **A soak across time boundaries.** The acceptance checks repeat on a schedule for at least 24 hours and across
   every boundary the frame names (by default the hour, UTC midnight and local midnight). A boundary that cannot be
   crossed inside the stage (month end, a daylight-saving change, a credential expiry) is a residual with the
   allowed reason "elapsed time", an owner and a date.

**The forecast splits in two, and each certificate states both.**

| Certificate | Before implementation signoff | After implementation signoff |
|---|---|---|
| Research certificate (Stage 8) | forecast: the build-findable share of the §3.12 total | forecast: the rest. The 95% bound is the §3.12 bound unsplit, because an assumed share may not tighten a bound |
| Built certificate (Stage 9) | observed: counted changes since the research signoff plus material built-stage findings, against that forecast | forecast: material findings × (1 − c) ÷ c, where c is the 95% lower bound of the mutant kill rate, plus the research certificate's invisible estimate scaled by (1 − share) |

The build-findable share is 0.585, labeled "share assumed": the replay figure pools build, probe, production and
operator finds, so it overstates what building alone finds. The pilot's own split replaces it.

**Gate rows (built gate, `gate.sh built-run`; rows 1–19 are not re-run).**

| Gate row | Exact criterion |
|---|---|
| 20. Built snapshot | The research certificate is signed, has no FAIL row and no reopen after it. Every build wave the frame names is recorded done. The built snapshot's commit equals the artifact's HEAD now, and equals the snapshot the last counted built round examined |
| 21. Repro | 0 open material findings. Every material finding has a tool-recorded failing run of its test command, and that command, re-run now on the snapshot, passes. Findings without a failing test are listed as `rejected-no-repro` and are not material |
| 22. Harness mutation | The mutation run is on this snapshot and its unmutated baseline passed. At least 10 mutants, and at least one per acceptance row. 0 survivors: each earlier survivor is a fixed finding and the re-run killed it. An "equivalent" mutant carries a reason and a rater. The kill rate is printed |
| 23. As-built contact | Every required probe and acceptance row has a run on this snapshot, exit 0, with the recorded environment showing an empty `HOME`, `PATH=/usr/bin:/bin` and `/bin/bash` 3.2, and a negative control or a reason |
| 24. Soak | At least 24 hours and 24 samples after the last fix, 0 failing samples, and every named boundary crossed or declared as an elapsed-time residual with an owner and a date |
| 25. Built rounds | At least one counted built round on this snapshot. All slots complete, at least 2 vendor families. Stopped quiet (the profile's quiet-round count) or at the built-round cap, never past it |

**Caps (additions to §6.5; bounded like every other loop).**

| Loop | Cap | After the cap |
|---|---|---|
| Built rounds | 3 (lite), 4 (standard), 6 (full); the cap round never edits | Certifies with named known rows |
| Dead or voided built-round slot | 2 re-runs (the §3.8 cap) | Another live vendor, "reduced diversity" printed |
| Mutation re-run after a harness fix | Once per survivor | The survivor stays a named known row |
| Soak restart after a fix | 2 restarts | The failing check is a named known row with an owner |
| Stage 9 time | 1 day (lite), 2 (standard), 3 (full) of agent time, soak elapsed time excluded; the §6.5 overrun rule at 1.5 × | Open rows become dated carried rows with defaults |

**Price.** Lite: up to 3 built rounds of 8 reviewer reads (24 reads), one mutation run (machine time), 1 agent-day,
and at least 24 hours of elapsed soak. Standard: up to 4 rounds of 16 reads and 2 agent-days. It buys the move of
build-findable holes from after the claim to before it; the size is unmodeled until the pilot measures it (audit
row 2). Every number in this section is an assumed input until then (§6.6).

**Not changed.** Rows 1–17, their thresholds, the rubric and the §5 change control. A Stage 9 finding is a counted
change against the before-implementation-signoff forecast, not a take-back; the §5.3 take-back test still reads the
total.

**Signing the implementation.** Added 2026-10-05 (v1.2, build wave E3d); nothing above is deleted. "Before you sign
the implementation" had no signature behind it: the signing tool could sign the frame and the research certificate,
and nothing for what was built. It now has one, and a built certificate is not "done" without it.

1. After `gate.sh built-run` certifies, the agent runs `cc-research built signoff --program <slug>`. It prints the
   built certificate's lines, the file your signature will pin and its hash, the signature state, and your exact
   command. It signs nothing; an agent cannot.
2. You read the built certificate and sign in your own terminal:
   `cc-signoff research:<slug>/implementation --evidence <what you read>`. The same three protections as every other
   signature apply (§8 item 4): the tool refuses when any ancestor process is an agent; the signature pins the
   newest built certificate by path and hash, so one changed byte makes it stale; and a record written under an
   agent, or with no recorded ancestry, is read as void and authorises nothing. The tool also refuses while the
   registry is not `build-certified`, or when no built certificate exists.
3. Your one command also moves the registry: it runs `gate.sh built-signed`, which sets a third v1.2 state,
   `certified → build-certifying → build-certified → implementation-signed → closed`. `gate.sh` stays the registry's
   only writer and makes the move only on a valid signature of the newest built certificate. The state is active
   for the §3.1 exemption and the §4.2 research block, like the two before it, until `gate.sh close`.
4. What the signature gates. `gate.sh close` refuses a `build-certified` program until it is signed. A build wave
   that follows implementation signoff fires with `handoff-fire.sh --requires-gate <slug> --gate-after-signoff`,
   which refuses in every state but `implementation-signed`. `gate.sh render` adds the signature state to the
   built line: "implementation signed by the operator <date>", "not signed", or the void or stale signature by
   name.
5. A signature does not outlive what it covers. If the built certificate changes, or a fix after signoff is
   certified again (`gate.sh built-freeze --refreeze`, then `built-run` writes the next certificate), the old
   signature no longer counts: `built-signed` sets the registry back to `build-certified`, and the new certificate
   needs your signature again.

Not gated: closing a program from `build-certifying` (an abandoned Stage 9 is not a "done" claim), and a 1.1 program,
which never enters these states.

## 12. Method v1.2: contact and build-to-learn stop on yield; decisions below 90 are tagged by what blocks them

Added 2026-10-04 under ruling `1bf69e5c1775` (§9), change (c), from audit row 7. Nothing in §3 is deleted. It
applies to a program whose signed frame carries `method_version` 1.2 or later. The triage study
(`docs/research/triage-precision-study-2026-10-04/REPORT.md`) found about 9 changes after signoff per program
whatever the triage filter, so the lever is the front end, which §6.4 already ranks first.

**12.1 Stages 3 and 5 end on yield, not on the stage clock.**

- A **counted probe** is one recorded inside the stage that could fail (§3.4). A probe that could not fail teaches
  nothing and is ignored.
- A **find** is a counted probe tied by the tool to a record it produced: a refuted premise, a hole, a counted
  change, a residual or a frame row. A counted probe that exited nonzero and has no such record yet also counts as
  a find, so an unexplained failure never reads as quiet.
- A **quiet probe** is a counted probe that passed and produced no find.
- **K** is 3 (lite), 4 (standard), 5 (full).
- **Yield** is the finds among the last 2K counted probes, divided by the agent-days those probes took.
- **Value of information** is yield × the escape cost you gave at intake (`escape_cost_days`, §9 decision 5). It
  reads: research days saved per research day spent.

The stage **continues** while the last K counted probes are not all quiet, or value of information is above 1. It
**stops** when the last K are quiet and value of information is at most 1. `cc-research budget end` refuses to end
stage 3 or 5 while the rule says continue, and records the stop reason and its numbers when it ends.

**Hard ceilings stay (§6.5).** The stage ends regardless at 4 × its stage budget in agent-days or 60 counted
probes, whichever comes first, printed as "stopped at the ceiling", and the unworked cells are declared residuals
as §3.6 already requires. The §6.5 overrun packet at 1.5 × is unchanged: you are told, and the default "proceed"
now means "keep probing while yield pays", up to the ceiling.

**12.2 A decision below 90 is tagged by what blocks it, and only two tags may be defaulted or carried.** The tag
is computed from the decision's tally, never typed:

| Tag | Computed when | May be defaulted (class B) or carried (class C, set) |
|---|---|---|
| research | A load-bearing premise is below its required level and a probe could raise it, or the flip probe has not run | No. It gets more research, up to twice its intake timebox. At that ceiling it converts as §3.5 says, printed "defaulted at the research ceiling", and the extension below is offered |
| production | Every remaining gap is a premise named by a residual whose reason is production traffic, a tenant not held, or elapsed time | Yes |
| operator | The decision rests on no factual premise, or every remaining gap is your eye, your value or a private fact | Yes |

**12.3 A priced research extension per decision, on your menu.** `cc-research menu` lists one item for each
decision below 90 whose tag is research: the conviction now, the premises still below level, the highest
conviction an extension could reach, and the price (one more intake timebox of research on that decision). You buy
it with `cc-signoff research:<program>/extend-decision/<decision id>`, at most once per decision. It is quoted as a
change to that decision's conviction, never as a yield.

**Gate rows (research gate; both read PASS as "not applicable" under a 1.1 frame).**

| Gate row | Exact criterion |
|---|---|
| 18. Yield stop | Stages 3 and 5 have ended. Recomputed now from the probe records as of each end: the rule said stop, or a ceiling was reached and is named. The escape cost is a finite number |
| 19. Decision blockers | Every decision below 90 that is defaulted or carried has the tag production or operator, recomputed now, or reached its research ceiling (twice its timebox, plus one timebox if an extension was signed). At most one valid extension signature per decision |

**Caps (additions to §6.5).**

| Loop | Cap | After the cap |
|---|---|---|
| Contact (stage 3) and skeleton (stage 5) probing | 4 × the stage budget in agent-days, or 60 counted probes | "Stopped at the ceiling"; unworked cells are residuals |
| Research on a decision tagged research | Twice its intake timebox | Class B or C as in §3.5, "defaulted at the research ceiling" |
| Research extension | 1 per decision, operator-only | The decision keeps its route |

**Price.** At most 3 extra stage budgets on each of stages 3 and 5: 5.25 agent-days above the lite budget (0.75 and
1.0 days), 12 above standard. The contract page's ceiling (§6.1) must include it. Each extension costs one decision
timebox. What it buys is unmeasured: contact is the only lever on the invisible share (§6.4), and the model cannot
price front-end effort yet, because 11 of 16 replay plans had 0 front-end days (audit row 7). K, the 2K window, the
4 × ceiling, the 60-probe ceiling and the 2 × decision ceiling are assumed inputs. The stop record and the per-probe
find records are the data the pilot needs to fit them.

**Not changed.** Rows 1–17 and their thresholds. Row 16 still requires the overrun packet past 1.5 ×. §3.5's routes
are unchanged for a decision tagged production or operator.
