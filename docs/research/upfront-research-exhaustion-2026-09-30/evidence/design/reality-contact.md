# Reality-Contact-First upfront research (RCF): exhaustive, no take-backs, and finite

Design unit: reality-contact angle. Written 2026-09-30, revised the same day after the 15:26 CDT reboot
(see "Revision log" at the end). Read-only: no repository or transcript was edited.
Inputs read in full: `/tmp/rescomp/taxonomy.md`, `/tmp/rescomp/forensics/shard-0..7.md`,
`/tmp/rescomp/internal/{research-machinery,close-assertion,plan-lifecycle,greenfield-cases}.md`,
`/tmp/rescomp/external/{stopping-rules,unseen-estimation,llm-failure-modes,epistemic-limits,systems-engineering}.md`,
and the hole ledger `/tmp/rescomp/taxonomy_holes.py`. Spot checks run for this design are cited inline as
`cmd => output`.

**Hole ids.** "hole N" or "#N" always means row N of the canonical ledger `/tmp/rescomp/taxonomy_holes.py`
(ids 1-200). Shard-7's own hole labels H1-H21 are ledger rows 180-200 (`shard-7.md:135-155`), and this
document never uses those labels. Below, "H1"-"H7" always means the seven contact classes of §1.4, and
hole records in the schemas are `HR-nnn`.

---

## 0. Answer first

1. **The loop is research closed by the wrong kind of evidence, at the wrong time, against no fixed frame.**
   It is not a shortage of research. In the 200-hole ledger, 135 holes (67.5%) belong to classes whose
   prevention step is *executed evidence*. Those same classes hold 65 of the 95 decision-changing holes.
   The classes are:
   - C3: a primary read or a live query;
   - C4: an enumeration command with a cross-check;
   - C5: a check shown red on a planted defect;
   - C9: a probe on the target environment;
   - C10: a re-run validity check;
   - C11: a measured ceiling.

   Today the evidence ladder is climbed one rung per operator push: blog, then source, then code, then
   execution (`shard-6.md` pattern 3). RCF climbs the whole ladder before the first claim.
2. **Desk proposes, contact disposes.** Desk research produces hypotheses, options, census candidates and
   premises. Only an executed probe can close a load-bearing premise or certify an acceptance row, and it
   must be recorded by a tool with its command, environment and raw output. The exit gate refuses any
   load-bearing premise that sits below its required evidence tier.
   - Every open question is first sorted as *complicated* (desk-closable by a primary read, Cynefin's
     "known unknowns") or *contact-only* (one of seven classes H1-H7 that exhaustive desk work has
     been documented to miss: rare interleavings, emergent load behavior, model-vs-reality gaps,
     integration, user-need validity, complex-domain unknowns, deployment state;
     `external/epistemic-limits.md` §3). Desk time is spent only on the first kind.
   - A desk re-check everyone expects to pass carries almost no information (Reinertsen: a binary
     test is most informative near a 50% failure rate; `epistemic-limits.md` §1.3). That is why
     re-reading does not converge and probing does.
3. **Contact comes first, not last.** Right after intake and census, a measure-first **Contact Wave (W0)**
   measures the incumbent system, the environments and the ceilings, and it does this *before* design.
   The evidence for doing it first:
   - The problem statements were usually wrong: 10 of 12 original constraint cells were later falsified
     or amended (`plan-lifecycle.md` §5.3).
   - The W0 measure wave reshaped W3 (hole 53, `shard-1.md` case 20).
4. **Research builds the executable spec and a throwaway contact skeleton.**
   - The acceptance harness must go red before build and red and green on fixtures. This is the pattern of
     the one plan that closed and stayed closed (reso `DOCS_CONSOLIDATION_100P.md:2059-2099`).
   - The skeleton is a tracer bullet across every environment boundary: launchd with `/bin/bash` 3.2, the
     Linux build, the tenant, the device OS, and handed commands run with no stdin.
   - Contact coverage is a **finite grid**, not an open search: every in-scope component × the seven
     contact classes H1-H7. Each applicable cell names its instrument (model check, load and fault
     run on the skeleton, spike on the real dependency, end-to-end skeleton, operator prototype,
     set-based probe, deploy and rollback rehearsal), and the gate requires an executed probe in
     every applicable cell. An empty cell is a visible gap, not a future "one more thing" (the STPA
     completeness grid, `external/systems-engineering.md` §4).
   - A decision whose deciding fact cannot exist before build is carried **as a set**, the way Toyota
     carries design alternatives. It records a narrowing probe scheduled in build wave 1, a
     pre-declared branch for each member, and a revision budget. When build later eliminates a member,
     that is a planned narrowing step, not a take-back (`epistemic-limits.md` §1.5, §1.9).
5. **"100.00/100.00" becomes a ratified, checkable definition.** It has four parts:
   - 100.00% of the operator-signed frame's rows are closed by executed evidence;
   - every decision is ruled as a point, or carried as a set whose narrowing probe, branches and budget
     are signed;
   - a certified bound on unseen material holes exists (from cross-family blind panels, capture-recapture
     and seeded holes);
   - the residual is declared, owned and dated.

   The literal "no unknown left anywhere" cannot be certified short of examining nearly the whole
   universe (n ≥ 0.95N; `stopping-rules.md` §2). So the method states what it certifies and prices
   anything more.
6. **The frame is fixed with the operator at intake:**
   - mine the history first;
   - run a short interview of 12 questions at most;
   - write a manifest of 16 mandatory axes, each in scope or excluded in the operator's own words;
   - set a materiality rule and a "perfection dial";
   - map every historical re-ask frame to an axis.

   The operator signs the frame with `cc-signoff`, which pins it by content.
7. **Certification runs before any claim, on a frozen snapshot, with a hard round cap** of one full
   round plus two delta rounds. It includes a **re-ask rehearsal**, which replays the operator's
   historical question frames against the frozen artifact so they have nothing left to trigger. It stops
   on estimators, not on a feeling. There are no open-ended critic loops.
8. **After the gate, "are we 100.00/100.00?" is answered by `cc-research verdict`.** That command
   re-executes the harness and reads the ledger; it never generates a fresh critique. Both answers carry
   an evidence burden:
   - A "no" must cite a typed, receipted, material hole row.
   - A "yes" must cite the verdict re-executed this turn.

   Searching further is an explicit, priced verb (`extend`).
9. **A post-gate hole reopens only its dependency closure** (premise → decision → row → wave). It is
   typed as a relabel, drift, a declared residual, an operator expansion, a material miss or a
   refinement. Only a material in-frame miss counts as a take-back; it is a measured defect of the method
   and feeds the seed library.
   - Severity is triaged the way aviation handles open problem reports (EASA AMC 20-189). Only a
     *Significant* item blocks: a safety, security, data-integrity or irreversibility hazard, or an
     unmitigated flip of a signed decision. Every other item stays open with a recorded justification
     and an owner, and does not reopen the baseline (`systems-engineering.md` §3).
   - The signed frame is a **baseline** with a presumption against change. Any change carries an
     impact quote before it is accepted, and a descope channel exists alongside the add channel.
     Evidence for holding the line: GAO found 72% cost growth in programs that changed requirements
     after development began, against 11% in programs that did not (`systems-engineering.md` §6).
10. **The timeline is a forecast built from cost classes.** Unit costs per evidence tier, census,
    decision and panel are spread across 4 accounts. A medium greenfield comes out at about 10.5-14
    working days of upfront research, plus a one-time 0.5-1 day probe-kit bootstrap on the first program.
    Past research phases took 1-2 days and then leaked for weeks (`greenfield-cases.md`).
    - Probes run in order of expected information per hour, so refutations land early and the re-plan
      loops stay small.
    - An overrun of 50% or more raises a decision packet.
    - The perfection dial is priced in advance. For example, 95% → 99% of estimated holes costs 7.6 → 18
      more panels (`unseen-estimation.md` §3.6).
11. **What to build:**
    - `bin/cc-research` (ledger, probe runner with negative controls, contact matrix, grid censuses,
      point and set decisions, estimator, gate, verdict);
    - a `research-program` skill and command;
    - three Workflows;
    - four hook changes;
    - replacing the quota prompts that force gaps ("Find 2-3 gaps", "List 3");
    - a one-time probe-kit bootstrap. Measured today, this machine lacks Java/TLC and `hypothesis`, its
      Docker daemon state cannot be read, and `gemini` and `pi` are not installed. The panel families
      available today are Anthropic, OpenAI (`codex`, logged in) and local open-weight models
      (`ollama`: gemma4 26B, qwen3-coder 30B, devstral 24B) (§10.3).

---

## 1. Why reality contact leads, and where it does not

### 1.1 Which holes an executed probe would have closed

| Class | n | DC | Prevention is executed evidence? | The probe that closes it |
|---|---|---|---|---|
| C3 unverified premise | 29 | 12 | yes | a primary read (E2), live query (E3) or measurement (E4) captured by the probe runner |
| C4 population never enumerated | 32 | 22 | yes (the census part) | an enumeration command plus an independent cross-check command |
| C5 instrument could not discriminate | 29 | 8 | yes | the check run red on a planted defect; re-execution instead of recall |
| C9 contact-only | 30 | 13 | yes | a probe on the target environment and the contact skeleton. 24 of 30 were probeable on this machine (`taxonomy.md` §C9) |
| C10 reality moved | 8 | 4 | yes | re-run recheck commands, a trunk re-read and a credential probe at the gate and at build start |
| C11 criterion never operationalized | 7 | 6 | yes | the ceiling measured first; the positive reference set shown to the operator (E6) |
| **Subtotal** | **135 (67.5%)** | **65 of 95** | | |
| C1, C2, C6, C7, C8 | 65 | 30 | structure borrowed from the other angles | a computed verdict, the intake interview, the index and trace check, freeze plus lint, and sequencing plus estimator stop. Each of these is also a program that is executed, not a judgment |

Receipt: `python3 /tmp/rescomp/taxonomy_stats.py` (class counts and DC). Sums are computed from its table.

**Caveat.** The taxonomy marks 64.5% of holes "desk-findable". RCF does not dispute that. It counts a
primary read captured by the tool as contact (tiers E2 and E3). What it forbids is closing a
load-bearing premise by recall or by secondary text. The 26 desk-findable C3 holes each needed "one read
of the primary source" (`taxonomy.md` §C3), which is the cheapest probe there is.

### 1.2 The corpus's positive controls are all contact-first

- **DOCS_CONSOLIDATION_100P.** reso `docs/plans/DOCS_CONSOLIDATION_100P.md:2059-2099`.
  - All 58 acceptance commands were executed against unmodified trunk *before* building. 45 were
    unsound.
  - They were replaced by one harness whose `--self-test` must go RED over known-bad fixtures and GREEN
    over known-good ones: "A gate nobody has seen fail is not a gate" (`:2099`).
  - The programme was complete in 25.75 h and was never reopened (`plan-lifecycle.md` §0.5).
- **LIMIT_RECOVER_FLEET_V2 W0.** `docs/plans/LIMIT_RECOVER_FLEET_V2.md:158-171, 575-590`. A
  measurement wave ran before any build:
  - Placeholders were replaced by measured defaults: `LR_RECR_SCHEDULE` went from 10,25,40 to 5,15,30,45.
  - It found that "the design's '5-6 concurrent requests' band is unmeasured on this machine".
  - It found that "2.1.114 parks at an invalid-settings dialog".
  - W0-W6 then landed in about 1.5 days.
- **/ground-up Phase 1**, "measure the incumbent to death" (`skills/ground-up/SKILL.md:22`), and its ban
  on superlatives (`:14-18`).
- **Negative controls:**
  - LIMIT_RECOVER_100P was COMPLETE on n=1 and reopened when a real n=5 run recovered 1 of 5
    (`LIMIT_RECOVER_100P.md:319-321`). It then took 30 `/goal` conditions in 22 days
    (`plan-lifecycle.md` §4.1).
  - VoiceInk: "every pass so far has been a *reading* … the entire class of error that only a compiler or
    a running app reveals is untouched". Contact then found D22-D24 (`greenfield-cases.md` mechanism 1).
  - Denver read "LIVE" while an authenticated read found `floor_plan_element=0` (`plan-lifecycle.md` §4.4).

### 1.3 Evidence tiers (the ladder)

| Tier | Name | What counts | Can it close a load-bearing claim? |
|---|---|---|---|
| E0 | recall | memory, "as I said", a predecessor's summary | never |
| E1 | secondary text | vendor README, blog, plan prose, code comment or docblock, an index or memory entry, an inherited table row | never; allowed only for non-load-bearing context, and flagged |
| E2 | primary static read | code at a sha, the vendor's *rules* or spec (not the README), a config file, CONTRIBUTING, captured as `cmd => output` | yes, for claims about text or code |
| E3 | live read | a query of the live store, process, registry, trunk, sibling sessions, a credential's expiry or a tenant, stamped with a TTL | yes, for claims about current state |
| E4 | measurement | n ≥ 5, a load control, a harness whose payload matches production, raw output kept | yes, for claims about behavior or quantity on this machine |
| E5 | target-environment execution | run in the deployment context: the scheduler (launchd `env -i`, `/bin/bash` 3.2), the OS or device version, the build image, the tenant, the pipeline, the operator's `!` shell with stdin at `/dev/null` | yes, and it is required for deployment-context behavior |
| E6 | operator contact | the operator's eye on a prototype or a positive reference set; operator-held facts elicited | yes, and it is required for taste, intent and private facts |

**The required tier depends on where the truth lives:**
- code text needs E2;
- current state needs E3 with a TTL;
- behavior or quantity needs E4;
- behavior in the deployment context needs E5;
- taste, intent or private facts need E6.

A premise is **risky**, and therefore gated, when any registered decision or acceptance row names it.
Tiers are *computed* from the probe record written by `cc-research probe run`. They are never typed in by
hand.

### 1.4 What desk research cannot close: the contact-class matrix (H1-H7)

`external/epistemic-limits.md` §3 collects seven hole classes. For each one, either the source says the
information does not exist before interaction (Cynefin: cause and effect are known "only in
retrospect"), or a documented case shows exhaustive desk methods ran and still missed it. For example,
AWS's DynamoDB design passed "deep design reviews, code reviews, static code analysis, stress testing,
fault-injection testing" and informal proofs, and TLA+ still "Found 3 bugs, some requiring traces of 35
steps" (Newcombe et al. 2014, pp.1, 3, 7). RCF turns the seven classes into the columns of a per-program
grid (`contact_matrix.json`, §5).

| Col | Contact class | Instrument inside research | Required tier | Stop signal for the cell | Ledger holes it would have caught |
|---|---|---|---|---|---|
| H1 | Rare interleavings, concurrency, recovery | an executable spec plus exhaustive model check (TLC, or a `hypothesis` stateful test, or a small-scope enumeration script) of the design **and of every proposed fix**. AWS found "a bug in the first proposed fix" | E4 | clean on the stated safety and **liveness** properties at a declared bound. The property list is itself a census, because AWS missed a liveness bug "as we did not check liveness" | 126 (last-writer-wins), 142 (lockless second hop), 191 (ownerless lock) |
| H2 | Emergent load and feedback behavior | load and fault runs on the contact skeleton at production n | E4/E5 | behavior inside the declared load and fault envelope meets its threshold, with no unexplained non-linearity | 12 (±20% load contamination), 48 (n=1 cold latencies), 122 (a shaper kept on n=1) |
| H3 | Model-vs-reality gap: the real dependency, OS, library or API differs from the one the plan describes | a spike against the real dependency (thrown away) | E3-E5 | every load-bearing assumption about the dependency has a spike receipt | 41, 82, 131 (stubbed `it2`), 144 (pandoc never run), 146, 153 (a simulator in place of the device) |
| H4 | Integration and configuration: verified parts, broken whole | the contact skeleton end to end in the real configuration, re-run after any configuration change ("test as you fly") | E5 | the slice passes in the real configuration | 26, 91, 92 (launchd with bash 3.2), 94, 95, 98, 116 |
| H5 | User-need validity | an E6 operator-contact prototype or a positive reference set, before the spec is signed (FDA 820.30 separates validation from verification) | E6 | the operator completes the core task on the prototype; no new requirement category appears | 62, 65, 66, 79, 198 |
| H6 | Complex-domain unknowns | set-based decisions with safe-to-fail probes and a declared revision budget (Toyota; Loch et al.) | E4-E6 | the probes stop changing the decision, or the set is carried into build with a narrowing probe | 69 (candidates truncated to ≤4B), 157 (loudness target needs a limiter, found by trying), 181 (base version settled silently) |
| H7 | Deployment and operational state | a dry-run deploy plus a rollback rehearsal; kill switches and hard limits designed in (Knight Capital: a legacy defect plus an incorrect deploy lost more than $460M in 45 minutes) | E5 | rehearsed deploy and rollback succeed, and the guardrail trips in a drill | 24, 34, 43, 96, 121, 170 |

Rows are components (or subsystems) from the frame. A cell is `n/a` only with a one-line reason that the
P1 critic can challenge. **The matrix is how "exhaustive" becomes finite for contact.** An empty
applicable cell fails G4. A cell cannot close on a document; it closes only on an executed probe or a
set-decision record.

Receipt for the hole mapping: `/tmp/rescomp/design/.ledger_dump.txt` (a dump of `taxonomy_holes.py`).
The listed rows are mostly C9 and C5, with C11, C4, C10, C1 and C2u among them. The column assignment
is this unit's judgment, not a taxonomy field.

---

## 2. What "100.00/100.00" means under RCF

The operator ratifies this **standing definition** once. It is reused by every program.

- **Research 100.00/100.00** holds only when all of these hold on the frozen snapshot:
  - (a) Every row of the ratified acceptance matrix is SOUND, and its research-phase evidence is at its
    required tier.
  - (b) Every registered decision is ruled as a point, or carried as a set that meets G6.
  - (b2) Every applicable cell of the contact matrix holds an executed probe, a set record or a residual
    entry (G4).
  - (c) The certification gates are met at the chosen dial. Cross-family blind panels and seeded holes
    give an estimated count of unseen *material* holes below the threshold (default < 1, by the Chao2
    lower bound).
  - (d) Every item that cannot be closed is in the declared residual, with an owner, a date and a
    verification command.
  - (e) The operator has signed the content hash.

  In NASA's terms this is "maturity sufficient to begin" the next phase, with every TBD and TBR "clearly
  identified with acceptable plans and schedule for their disposition" (NPR 7123.1D App. G;
  `systems-engineering.md` §1). `residual.json` is that TBD/TBR ledger. Known unknowns do not block;
  unnamed ones are the failure mode.
- **Completeness is relative to named sources.** Requirements theory holds that external completeness
  "is a relative measure … cannot be defined in absolute terms" (Zowghi and Gervasi 2003, quoted in
  `systems-engineering.md` §5). So the frame carries an `external_sources` census: repo, trunk, sibling
  plans, transcripts, `msg`, vendor rules pages, the upstream issue tracker, access logs, the public
  mirror, and so on. The verdict states completeness against that list. Several historical "one more
  things" were a source consulted for the first time: the issue tracker (#182), access logs (#111), the
  public mirror (#187), and stores outside our own (#57). Under RCF each would have been a census
  member at P1, or a visible frame change after the gate.
- **Built, Deployed and Live-verified 100.00** are separate axes of the verdict vector (§7). The same
  harness computes them after build, and "live" means a content read of the deliverable, not a deploy
  status (the Denver lesson).
- **Not promised:**
  - zero unknowns outside the ratified frame, which cannot be certified (n ≥ 0.95N;
    `stopping-rules.md` §2; not identifiable from overlap alone, Link 2003);
  - genuinely new operator requirements;
  - the world changing after the gate.

  Each of these is a *typed event*, not a take-back.
- **Promised:** no signed row or decision is reversed except through a typed, receipted, material
  in-frame hole. Each such reversal is scoped, counted, and fed back into the method. Narrowing a signed
  set decision along its pre-written branch is not a reversal.
- **Baseline to beat:** 200 holes over 88 re-asks is about 2.3 holes per ask, of which about 1.1 were
  decision-changing (95/88).

---

## 3. The pipeline: P0 to P7

```
P0 Intake + frame ratification ─► P1 Prior art + census ─► P2 Premise register + Contact Wave W0
   (operator signs frame)                                      (measure reality BEFORE design)
                                                                          │
P7 Exit gate + operator signoff ◄─ P6 Certification ◄─ P5 Freeze ◄─ P4 Executable spec + contact
   (build may fire only now)        (seeded, blind,      + integrate    skeleton + model check +
                                     cross-family,                       fault injection + load +
                                     re-ask rehearsal)                   deploy rehearsal (H1-H7)
                                                                              ▲
                                                 P3 Option probes + decisions (point or set) ─┘
```

Only three loops are allowed:
- P2/P4 → P3: a probe refutes a premise, and only the decisions in that premise's dependency closure are
  revised.
- P4 → P3: the skeleton refutes an option, and only that decision reopens.
- P6: at most 3 rounds.

Nothing else loops. Each phase has a sub-gate, `cc-research gate --phase Pn`, which is also the `--goal`
of the dispatched session that runs the phase.

### P0: Intake and frame ratification (C2, C11, C1 prevention)

**I1. Mine before asking.** The intake dossier comes from read-only, parallel sweeps:
- **Prior art:** `cc-memory-search <terms>`, a grep over `docs/research` (406 entries, no index:
  `ls docs/research | wc -l => 406`), `docs/plans`, sibling repos, and transcripts of the topic.
- **Operator history:** `msg search`/`msg with` for the counterparties named; `cc-decide list --all`;
  the mission board; and CLAUDE.md house rules that act as acceptance criteria (for example the
  one-command preference and plain identifiers; holes 198 and 58).
- **External-source census:** the `external_sources` list of §2, seeded here and completed in P1.
- **Topic lock:** a live-owner check through `cc-sessions`/`cc-owner` and plan lineage, using a positive
  liveness signal (C6: two leads, three plans for one topic, hole 104).

**I2. Interview**: at most 12 questions, asked once, answer-first, each with a recommended default:
1. Who or what consumes the deliverable, and how is it installed: an agent, a human or CI (#198)?
2. Where does it run, and on what exactly: host, OS or device versions, scheduler, tenant (#191, #146,
   #153)?
3. What keeps it alive, what expires, and who re-authenticates (the sevenrooms laptop dependency, #168,
   `greenfield-cases.md` mechanism 8)?
4. Which prior decisions or private facts bind it (the apex domain #107, the in-person author agreement
   #194)?
5. What does "not lacking" mean? Name 3-5 positive references (C11; #66).
6. What is explicitly out of scope, in your words? This is the only legitimate exit for the existing
   negative-space rule (`skills/research-subagents/SKILL.md:800-803`), so answering it at intake turns
   that rule from a gap generator into a checklist.
7. What can only be verified in production or over time, and who owns that verification?
8. Which actions are irreversible or spend money?
9. Which dial setting do you want (§9.3), and what is the deadline?
10. Which upstreams or dependencies may move under us (#181: the fork's stale base)?
11. Where could this be published or mirrored (#187: the 3-hourly public mirror; #175: the daily push to
    a public fork)?
12. What must never regress (prior invariants; #159, the iOS PWA white flash)?

**I3. Frame manifest** (`frame.json`, §5). It has 16 mandatory axes. Each is either in scope with rows
and populations, or excluded with a quote of the operator's words.

| Axis | Covers | Hole receipts |
|---|---|---|
| A1 deliverable and consumer | who uses it, and how it gets installed | 198, 79 |
| A2 target environments | interpreter, OS or device, scheduler, CI image, tenant, network | 92, 95, 153 |
| A3 runtime lifecycle | where it lives, what keeps it alive, what expires, re-auth | 168, 16, 96 |
| A4 scale and fleet | production n, fleet case | 191, 193 |
| A5 concurrency | concurrent writers, sibling sessions, multi-step state | 126, 142 |
| A6 failure and recovery | the fault catalog, built as a grid (P1) | 191, 131 |
| A7 security, privacy, publication surfaces | exposure | 187, 175, 44 |
| A8 data integrity and irreversibility | seeds and write instruments against live rows; test records becoming real | 10; "test records became real guests" (`b03a348`, `greenfield-cases.md` mechanism 8) |
| A9 existing assets and prior invariants | use-what-exists, house rules | 110, 159, 139 |
| A10 upstream and dependency drift | fork base, vendor deprecations | 181, 182; `f483625` (`greenfield-cases.md` mechanism 5) |
| A11 operability and handoff | handed commands under `!`, one-command setup, friction reporting | 155, 97, 200 |
| A12 performance ceilings | measured, not asserted | 11, 15 |
| A13 cost and quota | | 109, 162 |
| A14 taste and UX | positive references, operator eye | 62, 65, 66 |
| A15 evidence and external sources | logs, analytics, issue trackers, stores we do not write | 111, 182, 57 |
| A16 decisions settled by default | freeze clauses, defaults shipped OFF | 181, 192 |

**I4. Frame critic, zero-allowed.**
- One Fable 5.1 critic and one non-Anthropic critic (`codex exec`; `gemini` is not installed, §10.3)
  read the manifest *and the census list*, not prose. In P1 they re-read the finished censuses and the
  contact matrix, including every `n/a` reason.
- Their only question: which unstated premises, missing axes, or baseline decisions are being settled by
  default?
- Each item needs a locus and the decision it would change. "None" is an expected answer.
- The critics exist because reviewers audit what the plan *says*, not its unstated premises
  (`shard-7.md` pattern 1). This is the *only* place a negative-space trigger runs: before ratification,
  never at close.

**I5. Map the operator's re-ask frames.** Every frame the operator has historically used maps to an axis
or to an explicit exclusion. The counts are crude regex counts over the 88 re-asks in
`/tmp/rescomp/loop_asks.json`, reproducible with `python3 /tmp/rescomp/design/reask_frames.py`, which
prints each regex. The pre-reboot tally's regexes were lost with /tmp. The rebuilt counts differ from it
by up to 8 per row (it had 59/24/19/18/15/14/9/5/4/4), but the order of the top frames holds.

| Frame | Count (of 88) | Verdict axis |
|---|---|---|
| correct/complete/covering | 51 | V1 |
| researched/exhausted | 30 | V1 |
| deployed and live | 20 | V6/V7 |
| decisions/steps outstanding | 17 | V2 |
| good to close/done | 15 | V9 |
| optimum ("nothing else can beat it") | 6 | V8 |
| no loose ends/follow-ons | 6 | V5, plus the computed follow-on line |
| no take-backs/final | 5 | V4 |
| saved/persisted | 3 | G7 |
| all waves/master plan | 1 | V6 |
| reachable-environment slice | not regex-countable; kept from the manual read | V5 split |
| **catchphrase "100th percentile" / "perfection"** | **80** | none: the superlative lint (I6) translates it |

The last row is the strongest single argument for I6. The superlative appears in 91% of completeness
asks (80 of 88), so an intake that does not translate it into numbered predicates leaves every future
ask unfalsifiable by construction.

**I6. Translate superlatives.** Every superlative becomes a predicate with a number. Its ceiling is a
P2 probe placeholder ("measure ceiling first"). Every hold carries an expiry date, so no hold like the
21-day "reply once 100th percentile complete" can recur (hole 56). Lint: zero predicates may match
`perfect|100th|maximal|best|exhaustive|absolute|flawless` without a numeric threshold.

**I7. Ratify.**
- The frame is landed on trunk, because `cc-signoff` pins `git rev-parse origin/main:<path>`
  (`bin/cc-signoff:15-19`).
- The agent advances the mission row to `awaiting-signoff`, and the operator runs `cc-signoff`.
- One changed byte reopens the row on the board (`bin/cc-signoff:15-19`), and after ratification the
  frame changes only through `changes.jsonl` with a cause.
- **The signed frame is a baseline, and change carries the burden of proof.** A change request lists
  its dependency closure (from `trace.json`) and a priced impact *before* it is accepted, as a NASA
  Configuration Control Board or a DoD Configuration Steering Board would require
  (`systems-engineering.md` §1-2, §6). A descope request is a first-class change type, not only an add.

**Sub-gate:** the G1 rows. **Locus:** L (the lead with the operator), because the operator exchange is
the asset.

### P1: Prior art and census (C4, C6)

- **Census populations.** Each gets one `census/<population>.json`:
  - options per decision, *including do-nothing and use-what-exists*;
  - candidates already in the repo (Parakeet Unified was already in the fork, hole 173);
  - callers, instances and checkouts (grep by *name*, not only by path; the wrong checkout, hole 88; the
    invisible caller `gen/config.py:76`, hole 90);
  - execution contexts (a typed-yes gate reading EOF under `!`, hole 155);
  - accounts and tenants (`claude-accounts`, M365 tenants: the example.com tenant was missed, hole 147);
  - concurrent actors (the generator that clobbered the operator's rankings, hole 126);
  - publication surfaces (hole 187);
  - prior invariants (hole 159);
  - evidence and external sources (the §2 `external_sources` list; holes 111, 182, 57);
  - hazards (the fault catalog, built as the STPA grid below);
  - state machines × inputs (the state × input grid below);
  - handed commands;
  - upstream dependencies with versions and dates;
  - decisions settled by default (holes 181, 192);
  - properties to model-check, safety *and* liveness, for every H1 cell (§1.4);
  - the contact matrix itself: components × H1-H7 (§1.4).
- **Grid censuses, where a finite grid exists.** A free list can only be checked against memory. A grid
  shows its own empty cells. Two grids come from high-assurance practice (`systems-engineering.md` §4-5):
  - **The hazard grid (STPA).** Every control action, write path or state transition is crossed with
    the four unsafe types: not provided; provided when it should not be; wrong timing or order; wrong
    duration. Examples it would have covered: "both write instruments unsafe" (hole 10); the
    crash handler failing open after a tool-list change (hole 44).
  - **The state × input grid** (Jaffe/Leveson completeness criteria). Every state machine is crossed
    with every input, including timeouts, startup, shutdown and offline, plus the requirement that
    transitions are deterministic. Example: the ownerless lock and the `set -e` bare-checkout death
    (hole 191).

  A cell is either a scenario with a fault-injection or model-check probe, or `n/a` with a reason. STPA
  caps the top-level list at "no more than 7 to 10" system-level hazards so that the grid stays
  reviewable. It also expects later steps to add hazards, and a new hazard adds rows downstream of it
  without reopening unrelated ones (STPA Handbook pp.19-20, 39).
- **Every census carries** a generating command, a *second, independent* cross-check command, and a
  coverage argument ("how a missing member would show up"). A census built by memory is inadmissible.
- **Prior research imports.** Each prior finding enters the premise register at its *original* tier
  (usually E1) until it is re-probed. Nothing inherited is trusted by default: 43 of 158 plan moves were
  claims that were false when written (`plan-lifecycle.md` §3).
- **Sub-gate:** the census rows of G2. **Locus:** S (a dispatched session), with the census fan-out run
  as a Workflow.

### P2: Premise register and Contact Wave W0 (C3, C9, C10, C11): reality first

1. **Extract premises.** An agent reads every draft artifact (intake dossier, census, prior-art notes,
   early design sketches). Each factual claim that a decision or row could depend on becomes a
   `premises.jsonl` row with a `truth_lives_in` field and a computed `required_tier`.
2. **Contact Wave W0** is a Workflow, `research-contact.mjs`, with one slot per probe. It runs, in this
   order:
   - **Environment census probe** (`cc-research probe-kit doctor`): interpreters, `env -i` scheduler
     emulation, OS and device versions, container availability, model-check tooling, cross-vendor CLI
     auth, credential expiry. Current state of this machine: see §10.3.
   - **Incumbent measurement**: measure the current system or baseline to death, with n ≥ 5 and a load
     control (hole 12: ±20% load contamination; hole 191: n=1).
   - **Ceilings**: for each superlative predicate, measure the physical or engine floor first (hole 11:
     "maximally fast" was never measured against the engine's 0.14 s).
   - **Premise probes**: each risky premise gets a probe at its required tier.
   - **Handed-command dry runs**: every command the plan will hand the operator is run by the agent with
     stdin at `/dev/null` (the `!` shell has no keyboard; hole 155), with `--dry-run` or against a
     sandbox (hole 97: a handed rotation command failed three times).
   - **Credential and lifetime probes**: token caveats and expiry, lock TTLs (holes 96, 142).
3. **Probe policy.** The runner enforces it; it is not left to judgment.
   - `mutates_live=false`, or a sandbox: a throwaway pane or session or launchd label, a sandbox `HOME`,
     or `--dry-run`. A research agent once killed its own subject (hole 49), and auto mode refuses to act
     on live sessions.
   - A probe that must mutate something live becomes an operator step filed with
     `cc-backlog needs --run`.
   - Raw output is persisted under `docs/research/<program>/evidence/<probe-id>/`, never in /tmp
     (hole 76: 5 of 9 artifacts existed only in /tmp; hole 176: harness and gold set only in /tmp).
     This rebuild is itself the proof: the 15:26 reboot wiped `/tmp/rescomp`.
   - Every probe declares its falsification condition, the output that would have refuted it.
   - **A probe must be able to fail (C5 applied to probes).** For E4 and E5 probes, where it is
     feasible, the runner also executes the probe against a known-bad input or environment and records
     that it reports the refuting outcome. Examples: a stub interpreter that lacks the feature, a
     fixture with the defect, a lock held by a dead pid. Where it is not feasible, the probe carries
     `control: none (reason)`, and the P6 panels see that flag.
   - **Refutation-rate check.** Historically, 27.2% of plan goalpost moves were claims false when
     written (`plan-lifecycle.md` §3). So a W0 that refutes 0 of ≥ 20 risky premises is a signal that
     the probes were chosen to pass, which is Reinertsen's zero-information test. The gate then
     requires a critic to re-sample 20% of the probe falsifiers. The rate is reported; it is not a
     quota.
4. **Refutations flow forward.** A refuted premise marks its dependents REVISE in `trace.json`. P3 then
   re-plans only those.

**Sub-gate:** G3, plus the environment rows of G4. **Locus:** S (a dispatched session driving a
Workflow; at least 8 same-shaped units, so it runs as a Workflow under the venue rule).

### P3: Option probes and decisions (C4 options, C3, A16)

- **Options census.** For every registered decision, the options census includes:
  - do-nothing;
  - use-what-exists (the existing Amplify CDN made a two-option decision moot, hole 110);
  - every option from any prior ranking, re-read (the 08-26 ranking that was never re-read, hole 108);
  - every candidate the repo already holds (hole 173), with candidates never truncated by an
    unstated cap (hole 69: only models of 4B or smaller were tested).
- **Trunk and sibling re-read before any recommendation** (C10). Option B had landed four hours before
  Option A was recommended (hole 119), and a sibling had changed the code 5.7 h earlier (hole 165).
- **Option probes.** Every *surviving* option gets a probe, usually a spike. Each decision records
  `what_would_flip` as a measurable condition, and a probe checks it.
- **Point or set** (Toyota set-based design; Loch et al.'s "selectionism"; `epistemic-limits.md` §1.5,
  §1.9).
  - **A point decision** is ruled now. Its `what_would_flip` has been probed, and it is outside the
    flip region.
  - **A set decision** is carried into build *by design*. Its `what_would_flip` can only be observed
    under conditions research cannot create (production traffic, an external tenant not held, elapsed
    time, the operator using the built thing). A set decision is admissible only with:
    - two to four members, each shown feasible by a probe ("feasibility before commitment");
    - a narrowing probe scheduled in build wave 1 with an owner and a date;
    - a pre-declared branch for each member: which plan items apply if that member wins;
    - a revision budget in hours, charged when a member is eliminated.

  Eliminating a member later is a scheduled step with a pre-written branch, not a take-back. Irreversible,
  high-uncertainty choices (data model, external contracts, consistency model) are the ones worth
  carrying as sets. Reversible ones are ruled as points, because researching a reversible choice to 100%
  buys an option nobody needed (`epistemic-limits.md` §1.8, labeled there as reasoning).
- **Rulings.** Rules for the conviction number:
  - **At 90% conviction or higher**, the agent rules. A `cc-decide` class A packet is the audit trail.
  - **Below 90% after contact, where the residue is a framing question**, the frontier ladder runs:
    Fable at stage 2, which writes a document only (CLAUDE.md § Frontier Tier Routing, T-a/T-b/T-c).
  - **Otherwise**, a class C packet goes to the operator with the number, the receipt and the measured
    options.
- **Settled defaults.** Decisions settled by default (freeze clauses, shipped-OFF defaults) are
  registered and ruled explicitly (holes 181, 192).

**Sub-gate:** G6. **Locus:** S.

### P4: Executable spec, contact skeleton, model check and fault injection (C5, C9, C11)

- **Acceptance harness**, the executable spec. It lives at `docs/research/<program>/harness.sh` and is
  promoted into the repo's `scripts/` at build.
  - It prints one row per check, echoing the command it ran and that command's own unpiped exit code.
  - `--self-test` goes RED over `fixtures/known-bad/`, and `--self-test-green` goes GREEN over
    `fixtures/known-good/` (the DOCS §9.1 properties).
  - Every row is classified with the DOCS §9 taxonomy: SOUND, NOT-A-COMMAND, ALREADY-PASSES,
    BLIND-TO-MECHANISM, FAILS-GREEN, MUTATES-STATE or BROKEN-SYNTAX. Only SOUND rows, and rows labeled as
    regression guards, are admitted.
  - Every row names its planted-defect control. **A predicate may certify only after it has gone red on
    a planted defect** (C5; `taxonomy.md` §C5).
- **Contact skeleton.** A throwaway worktree that holds the thinnest end-to-end path, crossing *every*
  boundary in the environment census once:
  - install a throwaway launchd label and observe a *scheduler-initiated* run, not a manual one
    (hole 92: `/bin/bash` 3.2 crashed on every trigger after a manual-run ✅);
  - a build in the target build image (hole 95: no `lsof` on the Linux Amplify image). The taxonomy counts
    hole 95 among the 6 rows unreachable on this machine. A container build of that image would bring
    it within reach, but only once the Docker daemon works (§10.3). Until then this cell is a declared
    residual;
  - one authenticated call on the real tenant, where research holds one (hole 134: tenant-only probes);
  - real files and artifacts through the pipeline (hole 146: launchd EDEADLK on dataless files; hole 199:
    online-only files *are* downloaded; hole 144: pandoc and merged cells; hole 67: a bake-off config that
    differed from the production request);
  - a handed command run with no stdin.

  The skeleton is a probe. By default its code is thrown away ("plan to throw one away; you will,
  anyhow", Brooks, secondary). Build wave 1 may instead *adopt* it as its tracer bullet, but only through
  that wave's normal review and gates, never by inheritance. Its evidence is kept either way. It is
  re-run after any configuration change, because the Mars Polar Lander systems test ran with mis-wired
  sensors and "was not repeated" (`epistemic-limits.md` §2.2, secondary).
- **Model checking or stateful property tests** for every H1 cell of the contact matrix (§1.4). Options
  are TLA+/TLC, Python `hypothesis` stateful tests, or an exhaustive small-scope enumeration script. The
  property list comes from the P1 census, liveness included. The cases they target:
  - the lockless second hop that erased custody (hole 142);
  - last-writer-wins on the operator's rankings (hole 126);
  - the ownerless lock (hole 191).

  **Every fix to a checked design is re-checked by the same instrument before it is integrated.** AWS
  found "a bug in the first proposed fix" (Newcombe et al. p.3). This is the contact form of the C7
  rule.
- **Fault injection** against every cell of the hazard grid: kill -9 mid-write, quota death, network
  drop, reboot, a partial write, clock or TTL expiry via a short-TTL time-compression probe.
- **Load runs on the skeleton** for every H2 cell. Formal methods are "not good for" "sustained emergent
  performance degradation", where "no logic bug is involved" (Newcombe et al. p.5).
- **Deploy and rollback rehearsal** for every H7 cell: a dry-run deploy, a rollback, and a guardrail or
  kill-switch drill.
- **Production-scale n where it is achievable:** synthetic rigs (FLEET_V2 W5's 5- and 30-session rig).
  Only production traffic, external tenants not held, elapsed calendar time and the operator's eye remain
  for the residual.

**Sub-gate:** G4 and G5. **Locus:** S, with teammates inside it: skeleton, harness and model check each
in its own worktree.

### P5: Freeze, integrate and check consistency (C7, C6)

- **Integration.** A single integrator owns the artifact and integrates each finding into the body.
  Appending is forbidden: §11 amendments that were never integrated shipped CAP 5000 (hole 115), and
  "The integration is the generator"
  (`docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md:14`).
- **`cc-research lint`** checks five things:
  - every number is consistent across sections;
  - no superseded value remains in a table;
  - every `file:line` anchor resolves at the sha;
  - there are no placeholders, no /tmp paths, and no superlatives without numbers;
  - every probe id cited exists.
- **`cc-research trace check`**: every finding in every research artifact maps to a plan item, row or
  decision, or to a recorded rejection with its reason. The cases it targets:
  - the dropped warm-connection fix (hole 172);
  - the dropped 744-line design axis (hole 61);
  - the truncated read that integrated 2 of 5 findings (hole 77).
- **A fresh-context reader reads the whole document after the last edit**, and the run is recorded as a
  probe (hole 180: 20 defects in a script-assembled plan nobody had re-read).
- **Freeze.** The snapshot sha is frozen. From here any edit needs a `changes.jsonl` entry and a delta
  round.

**Sub-gate:** G7 and G8. **Locus:** L or S with a single owner.

### P6: Certification (C8, and the C1/C2 relabels moved before the claim)

1. **Seeds.** An independent seeder, a separate dispatched session that never talks to the panels,
   makes a *seeded copy* of the frozen snapshot. It plants two kinds of seed:
   - **Representative seeds** (default 30), stratified by axis and drawn from the program's own hole
     types. Omission seeds, where a known census member or residual row is removed, are mandatory,
     because omissions are what panels miss (holes 187 and 87: a publication surface and a deciding
     data-residency gate, both omitted).
   - **Escape seeds** (default 10), adapted from the historical library built from the 200-hole ledger.
     Examples: "handed command needs stdin under `!`" (#155), "bash 3.2 under launchd" (#92), "stale
     index read as truth" (#183), "single-instance frame misses the fleet case" (#193), "publication
     surface unmodeled" (#187), "contact cell excused as n/a for a component that deploys" (new, §12).

   Escape seeds are a *separate hard-tail recall gate*. They are never the Mills denominator, which they
   would overestimate by about 2.5x (`unseen-estimation.md` §5 row I).
2. **Blind panels:** T ≥ 6, from at least 3 model families, at least 1 of them non-Anthropic. Each panel
   gets the seeded snapshot and the zero-allowed prompt (`llm-failure-modes.md` §3.3):
   - answer each acceptance row YES/NO/UNKNOWN with a receipt;
   - optionally propose items;
   - every item needs a locus, the decision or row it would flip, a frame class, and a probability plus
     falsifier;
   - "zero new items is an expected answer".

   No panel sees another panel's output. Adaptive follow-up waves are allowed for discovery, but they are
   kept *out* of the estimation matrix (Böhme 2021, `unseen-estimation.md` §2.8).

   **Panel admission.** A panel counts toward `families_min` only if its representative-seed recall is at
   least `panel_seed_recall_floor` (default 0.33). Otherwise a weak panel meets the diversity count while
   adding mostly noise. This matters on this machine today (§10.3): the families on hand are Anthropic,
   OpenAI via `codex`, and local open-weight models via `ollama` (Google gemma4 26B, Alibaba qwen3-coder
   30B, Mistral devstral 24B). None has been measured as a design reviewer. A local panel below the
   floor stays in the discovery pool but not in the estimator. If fewer than 3 families pass, the
   certificate is issued as degraded ("2 families") and says so.
3. **Adjudication.** A panel-blind adjudicator deduplicates the findings into a hole × panel matrix and
   logs every merge and split. A second adjudicator re-rates 20%, and agreement is reported.
   - Materiality is the §3.8 rubric, and it must name a registered id. If the two adjudicators disagree,
     the hole is treated as material.
   - **Real singletons stay in the matrix** (Deng 2024); step 4 decides which singletons are real.
4. **Reproduction is contact.** Every deduplicated candidate is dispositioned `real` or `false`
   before it enters the estimator input. Either a reproduction probe settles it (reproduce-first,
   FixedBench; for a behavioral claim), or the adjudicator does a primary read at E2/E3 (for a claim
   about text, code or state). Agreement across families only *prioritizes* the reproduction queue; it
   never substitutes for it, because LLM errors correlate across providers (Kim 2025). This matters for
   both directions of the estimate:
   - a false singleton left in the matrix inflates Q1, so Chao2 over-demands panels;
   - a real singleton removed deflates it, so Chao2 under-reports what is unseen (Deng 2024).

   Only real, material holes enter S_obs. A candidate that no probe or read can settle in research is
   typed `declared-residual` with its contact class, not left as `unconfirmed`.
5. **Estimators**, computed by `cc-research estimate` over material holes, with seeds excluded from
   S_obs:
   - Chao2, bias-corrected (the lower bound);
   - first- and second-order jackknife;
   - coverage and q0;
   - the expected new holes from one more panel;
   - `m_g` for g = 0.90/0.95/0.99;
   - Chao2 per family;
   - seed recall with 95% bounds.

   The report says in so many words that the estimates are **lower bounds**, because panel errors are
   correlated, more strongly within a provider but also across providers (Kim 2025).
6. **Integrate once, then run delta rounds.** Fixes are integrated as in P5. Then:
   - the probes, harness rows and model checks on the touched spans are **re-executed**, not re-read (a
     fix is a design too);
   - fresh blind panels (T ≥ 4) review only the touched spans and their dependents.

   **Round cap: 1 full plus 2 delta.** Delta-round findings must contain 0 material items.
7. **Re-ask rehearsal.** K = 12 fresh sessions each receive one of the operator's historical frames
   (§3 I5), using the operator's literal wording, together with the frozen artifact, the ledger and the
   verdict render. Each answer is typed:
   - an in-frame material miss fails the round, and it is fixed plus delta-verified;
   - a frame outside the ratified frame becomes an operator decision *now*: add it or exclude it, before
     signoff.

   This is contact with the operator's own instrument. The re-ask was "the first adversarial audit"
   (`taxonomy.md` answer 5), so RCF runs it before the claim.
8. **Stop rule.** Stop when G9 holds. If the round cap is reached with G9 still failing, the gate fails
   and a class C packet quotes three priced options:
   - extend by `m_g` panels (cost stated);
   - accept the current bound as residual;
   - reopen a named phase.

   Open-ended "find gaps" loops are banned. The evidence: 23/21/24/28 new holes per round, and
   37→…→16 over 13+ rounds (`taxonomy.md` §3).

**Sub-gate:** G9. **Locus:** S, driving the `research-certify.mjs` Workflow; the seeder runs in a
separate S session.

### P7: Exit gate and signoff

- `cc-research gate` computes G1-G12 (§6) and writes a verdict row.
- The agent advances the mission row to `awaiting-signoff`. The operator runs `cc-signoff` over the
  hashes of `frame.json`, `acceptance.json`, `residual.json` and `coverage.json`.
- **Build waves may fire only with gate PASS.** The harm this prevents: W1 fired while research slots
  r4/r7 were open (hole 137).
- A set decision (P3) does not block the gate. Its narrowing probe becomes build wave 1's first
  acceptance item.
- At build start, `cc-research premise due` re-runs every premise whose paths changed or whose TTL
  expired (C10).

### 3.8 The materiality rule (frozen at P0, used everywhere)

A finding is **material** when at least one of these holds, and it must name the id:
- **M1** it flips a registered decision, or moves its conviction across 90%;
- **M2** it flips an acceptance row's verdict, or shows that a row cannot discriminate;
- **M3** it moves a load-bearing premise's probe result outside its tolerance;
- **M4** it adds a census member that a row or decision must cover *and* that changes it;
- **M5** it is a safety, security, data-integrity or irreversibility hazard. M5 is always material, and
  the rule is to stop and surface it.

Everything else is a **refinement**, "something a build hits and fixes in minutes" (the TM2 stop-rule
ruling, `shard-7.md` case 83), and goes to the build backlog. Or it is cosmetic. A finding with no locus,
or no named id, is immaterial by default. That is the ISA 320 test in `llm-failure-modes.md` T5.

**Severity class (post-gate only).** This follows the open-problem-report classes of EASA AMC 20-189
(`systems-engineering.md` §3). Only the first class blocks.

| Class | Test | Effect on a signed program |
|---|---|---|
| Significant | M5, or an M1 flip of a signed decision with no mitigation | blocks: stop, surface, scoped reopen before any further build wave in its closure |
| Functional | M2, M3, M4, or a mitigated M1 | scoped reopen of its dependency closure; unrelated waves continue |
| Process | a method defect that cannot flip a decision or row (for example a missing receipt) | stays open, logged against the method report |
| Life-cycle data | a defect in an artifact's text only (a stale summary line) | stays open with its justification; fixed at the next integration |

---

## 4. Roles and model diversity

| Role | Who | Phase | Independence rule |
|---|---|---|---|
| Program lead | Opus 5.5 at effort high, in a dispatched session per phase | all | Holds the ledger through `cc-research`. **Never judges its own completeness**: the gate script does |
| Intake miners | `workflow-lean` slots, read-only | P0, P1 | Write only to the program's evidence dir |
| Census-takers | `workflow-lean`, Opus at effort medium | P1 | Every census carries a generating command and an *independent* cross-check |
| Premise extractor | Opus at effort high | P2 | A critic samples 20% of the register for tier errors |
| Probers | `workflow-lean` with Bash, Opus or Sonnet at effort medium (scoped coding) | P2-P4 | Probes only through `cc-research probe run`; `mutates_live=false` |
| Option scouts and finders | the `/research` wave primitive (`deep-research`) | P1, P3 | The quota gap prompt is replaced (§10.2) |
| Frame and premise critics | **Fable 5.1** plus one non-Anthropic (`codex exec`, the only logged-in non-Anthropic cloud CLI today) | P0, and P1 over the census and contact matrix | Zero-allowed. They read the census, contact matrix and manifest, not prose |
| Harness author and control verifier | two different agents | P4 | The verifier plants the defect and proves the check goes red; the author never self-certifies |
| Skeleton builder | a teammate in a throwaway worktree | P4 | Evidence persisted; code thrown away, or adopted by build wave 1 only through its review |
| Integrator | a single owner | P5, P6 | Integrates, never appends |
| Seeder | a separate dispatched session | P6 | Never communicates with panels or the adjudicator's dedup step |
| Certification panels | at least 6 panels from at least 3 families. Today: Anthropic (Opus with 2 context strategies, plus 1 Fable), OpenAI (`codex exec`, at least 2 panels), and local open-weight models via `ollama` (gemma4 26B, qwen3-coder 30B, devstral 24B), each admitted only above the seed-recall floor | P6 | Blind to each other and to seeds; same frozen snapshot |
| Adjudicators | two, Opus at effort xhigh (review) | P6 | Blind to panel identity; must name an id for materiality |
| Reproducer | a prober | P6, post-gate | A hole is real only once a probe reproduces it or a primary read confirms it; cross-family agreement only prioritizes |
| Gatekeeper | `cc-research gate`: **code, not a model** | P7 | Deterministic predicates |
| Operator | the human | P0, P3 below 90%, E6, P7 | Signs the frame and the gate; owns declared residuals |

**Where Fable is used** (bounded by `hooks/frontier-spawn-gate.sh` and the per-session budget), always
for a *different model's blind spots* rather than for a stronger model:
- (1) the P0/P1 frame critic, which hunts unstated premises and baseline decisions settled by default,
  the class the Opus critics missed (holes 181, 193, 194; `shard-7.md` pattern 1);
- (2) one certification panel, which adds *model* diversity inside the Anthropic family. It does not
  count as a separate family for `families_min`;
- (3) ladder stage 2 for a decision still below 90% after contact whose residue is framing.

Fable never runs probes and never edits files. **Fable is not sufficient diversity on its own**:
Opus and Fable share a provider, and correlation within one provider is higher (Kim 2025). So at least
one panel must be non-Anthropic. Local receipts, re-measured after the reboot (§10.3):
- `codex login status` => `Logged in using ChatGPT`, and `codex --version` => `codex-cli 0.147.0`;
- `ollama list` => gemma4:26b-a4b-it-qat, qwen3-coder:30b, devstral:24b, laguna-xs-2.1 and smaller
  models;
- `gemini`, `pi` and `grok` are not installed. `whence -p` under both a login and an interactive zsh
  found none of them, and neither did a `find` over `~/.local`, `/usr/local/bin`, `/opt/homebrew/bin`
  and `~/.bun`.

An earlier draft of this section listed `gemini` and `pi` as present, and that did not hold when
re-measured. Whether the binaries lived on a path the reboot removed or the original check was wrong,
it was a premise inherited without a fresh probe, which is class C3 in miniature. That is why
`probe-kit doctor` re-verifies the list at P0 of every program instead of trusting a design document.

**Why family diversity rather than more subagents.** In the simulation, going from 1 family to 5 raised
holes found from 140 to 184 and put JK2 on the truth (`unseen-estimation.md` §5, C→D). Ten Opus panels
behave more like one inspector with ten attempts.

---

## 5. Persisted artifacts and schemas

Everything lives in the project repo under `docs/research/<program-id>/`. JSON is used for records the
model must not casually rewrite, because "the model is less likely to inappropriately change or
overwrite JSON files" (Anthropic harness, `llm-failure-modes.md` T2). The directory is landed on trunk,
which `cc-signoff` pins, and it is never kept in /tmp.

```
docs/research/<program-id>/
  frame.json          acceptance.json      harness.sh  fixtures/{known-bad,known-good}/
  census/<pop>.json   premises.jsonl       probes.jsonl evidence/<probe-id>/{cmd,stdout,stderr,env.json}
  decisions.jsonl     holes.jsonl          coverage.json trace.json  residual.json
  contact_matrix.json verdicts.jsonl       changes.jsonl budget.json
  seeds/ (seeder-only; revealed after adjudication)
```

**frame.json**
```json
{ "program_id": "slug-YYYY-MM", "question": "operator ask, verbatim", "deliverable": "what exists when done",
  "consumer": {"who": "", "runs_where": "env id", "installed_by": "agent|human|ci"},
  "definition_of_complete": {"research": "G1-G11 PASS + signature", "built": "harness all green post-build",
                             "live": "live content-read rows green"},
  "axes": [{"id": "A1", "name": "", "status": "in|excluded", "exclusion_quote": "operator words|null",
            "rows": ["AC-001"], "populations": ["census id"]}],
  "decisions": ["D-01"], "materiality": {"rules": ["M1","M2","M3","M4","M5"], "rubric_version": "1"},
  "dial": {"panels_min": 6, "families_min": 3, "non_anthropic_min": 1, "unseen_material_max": 1.0,
           "jk2_residual_max": 2, "seed_rep_n": 30, "seed_rep_recall_min": 0.90, "seed_esc_n": 10,
           "seed_esc_recall_min": 0.80, "round_cap": 3, "meas_n_min": 5,
           "panel_seed_recall_floor": 0.33, "refutation_resample_min_premises": 20},
  "external_sources": [{"id": "S-07", "source": "upstream issue tracker", "access_cmd": "gh issue list -R owner/repo ...",
                        "status": "in|excluded", "exclusion_quote": "operator words|null"}],
  "reask_frames": [{"frame": "deployed and live", "axis": "V7"}],
  "residual_allowed": ["production-traffic", "external-tenant-not-held", "elapsed-calendar-time", "operator-eye"],
  "ratification": {"content_sha256": "", "signoff_id": "", "at": "ISO"} }
```

**acceptance.json** (rows)
```json
{ "id": "AC-017", "axis": "A3", "predicate": "plain sentence with a number", "check_cmd": "single line, prints evidence",
  "env": "env id from the environment census", "expect_prebuild": "RED|GREEN-regression-guard",
  "threshold": {"metric": "p90_ms", "op": "<=", "value": 1500, "ceiling_probe": "P-044"},
  "control": {"known_bad": "fixtures/known-bad/..", "red_proof_probe": "P-051", "known_good": "fixtures/known-good/.."},
  "n": 5, "load_control": true,
  "soundness": "SOUND|NOT-A-COMMAND|ALREADY-PASSES|BLIND-TO-MECHANISM|FAILS-GREEN|MUTATES-STATE|BROKEN-SYNTAX",
  "premises": ["PR-031"], "decisions": ["D-04"], "status": "draft|sound|reopened",
  "last_run": {"probe": "P-090", "exit": 1, "sha": "", "at": "ISO"} }
```

**census/<population>.json**
```json
{ "population": "callers of X | options for D-03 | candidates | checkouts | tenants | execution contexts | publication surfaces | concurrent actors | prior invariants | evidence and external sources | hazards (grid) | state machines x inputs (grid) | handed commands | upstream deps | defaults | model-check properties",
  "generating_cmds": ["rg -n 'name' ..."], "cross_check_cmd": "independent method",
  "members": [{"id": "", "desc": "", "source_line": "cmd output line"}], "coverage_argument": "how a missing member would show",
  "cross_check_diff": [], "validated_at": {"ts": "ISO", "sha": ""}, "critic": {"families": ["fable","openai"], "findings": []},
  "form": "list|grid",
  "grid": {"rows": "control actions | state machines", "cols": ["not-provided","provided-wrongly","wrong-timing-or-order","wrong-duration"],
           "cells": [{"row": "", "col": "", "scenario": "", "probe": "P-..|null", "na_reason": "text|null"}]} }
```
A grid census passes G2 only when every cell has a scenario with a probe, or `na_reason`. For a state
machine the columns are its inputs, including timeout, startup, shutdown and offline.

**contact_matrix.json**
```json
{ "rows": [{"component": "sync daemon", "cells": {
    "H1": {"applies": true, "instrument": "model-check", "properties": ["no lost write","eventually idle (liveness)"], "probes": ["P-061"], "status": "clean|finding|open"},
    "H2": {"applies": true, "instrument": "load-on-skeleton", "envelope": "n=30 sessions, 3x burst", "probes": ["P-070"], "status": ""},
    "H3": {"applies": true, "instrument": "spike-real-dependency", "probes": ["P-022"], "status": ""},
    "H4": {"applies": true, "instrument": "skeleton-e2e", "env_ids": ["launchd-bash32","tenant-dev"], "probes": ["P-080"], "status": ""},
    "H5": {"applies": false, "na_reason": "no human-facing surface; consumer is an agent (A1)"},
    "H6": {"applies": true, "instrument": "set-decision", "decision": "D-07", "status": "carried"},
    "H7": {"applies": true, "instrument": "dry-run-deploy+rollback+kill-switch-drill", "probes": ["P-091","P-092"], "status": ""} } }],
  "critic": {"families": ["fable","openai"], "findings": []} }
```

**premises.jsonl**
```json
{ "id": "PR-031", "claim": "one sentence", "load_bearing_for": ["D-04","AC-017"],
  "truth_lives_in": "code|live-state|behavior|target-env|operator", "required_tier": "E2|E3|E4|E5|E6",
  "achieved_tier": "computed from probes", "origin": {"source": "doc/path|url|memory", "tier": "E1"},
  "probe_ids": ["P-044"], "verdict": "holds|refuted|partial|unknown",
  "measured": {"value": 0, "unit": "", "n": 5}, "tolerance": "",
  "validated_at": {"ts": "ISO", "trunk_sha": "", "depends_on_paths": [""]},
  "ttl_class": "code-path|live-24h|external-7d|credential-expiry", "recheck_cmd": "" }
```

**probes.jsonl** (written only by `cc-research probe run`)
```json
{ "id": "P-044", "closes": ["PR-031","AC-017"],
  "kind": "read|live-read|measure|spike|skeleton|model-check|fault-inject|dry-run-deploy|canary|handed-cmd|read-through|operator-view|reproduce",
  "env": {"id": "launchd-bash32", "descriptor": {"interpreter": "/bin/bash 3.2.57", "PATH": "/usr/bin:/bin", "os": "15.7.9", "account": "", "tenant": ""}},
  "cmd": "exact", "stdin": "/dev/null", "n": 5, "control": "what lets it fail", "falsifier": "output that would refute",
  "negative_control": {"ran": true, "against": "known-bad env or fixture", "reported_refutation": true, "reason_if_not_run": null},
  "contact_cell": "sync daemon/H4",
  "raw": "evidence/P-044/", "exit": 0, "duration_s": 0, "result": "", "mutates_live": false,
  "sandbox": "throwaway-pane|sandbox-HOME|dry-run|none", "run_by": {"session": "", "model": ""}, "at": "ISO", "trunk_sha": "" }
```

**decisions.jsonl**
```json
{ "id": "D-04", "question": "", "options_census": "census/options-D-04.json",
  "options": [{"label": "do-nothing", "probe": "P-.."}, {"label": "use-what-exists", "probe": "P-.."}],
  "premises": ["PR-031"], "recommendation": "", "conviction": 92, "what_would_flip": "measurable condition",
  "flip_checked_by": "P-..", "ruled_by": "agent|operator|ladder", "cc_decide_id": "", "settled_by_default": false,
  "kind": "point|set", "reversible": true,
  "set": {"members": [{"label": "", "feasibility_probe": "P-..", "branch": ["plan item ids if this member wins"]}],
          "narrowing_probe": {"cmd": "", "env": "", "wave": "B1", "owner": "agent|operator", "due": "YYYY-MM-DD"},
          "revision_budget_h": 6, "why_not_now": "production-traffic|external-tenant-not-held|elapsed-calendar-time|operator-eye"},
  "status": "open|ruled|carried-set|reopened" }
```
A set decision is admissible only when `why_not_now` is one of the allowed residual classes and every
member has a feasibility probe.

**holes.jsonl** (append-only; one row per candidate, including seeds, which are revealed after adjudication)
```json
{ "id": "HR-017", "text": "", "locus": "file:line|probe|census member",
  "raised": {"by": "panel-3|rehearsal-7|operator|post-gate", "family": "openai", "blind": true,
             "phase": "P6-r1|P6-d1|rehearsal|post-gate|extend", "snapshot_sha": ""},
  "is_seed": false, "seed_kind": "rep|esc|null", "dup_of": null,
  "materiality": {"class": "M1|M2|M3|M4|M5|refinement|cosmetic", "names": "D-04|AC-017", "adjudicators": ["a1","a2"], "agree": true},
  "confirmed_by": {"probe": "P-..|null", "primary_read": "P-..|null", "families": 2}, "real": true,
  "severity_class": "significant|functional|process|lifecycle-data|null (pre-gate)",
  "frame_type": "in-frame-miss|relabel|operator-expansion|declared-residual|drift|self-inflicted|set-narrowing",
  "taxonomy_class": "C1..C11", "reopen_set": ["AC-..","D-.."],
  "disposition": {"kind": "fixed|rejected|residual|build-backlog|scope-grown", "ref": "sha|backlog id|decision id", "at": "ISO"} }
```

**coverage.json**: for each axis: `{code_sat, meaning_sat, census_complete, premises_at_tier: "x/y",
rows_sound: "x/y", probes_executed}`. Plus
`estimator: {T, families, S_obs_material, Q1, Q2, chao2_bc, jk1, jk2, coverage, q0, next_panel_expected,
m_g: {"0.90":0, "0.95":0, "0.99":0}, per_family_chao2: {}, seeds: {rep: {n, found, recall, lcb95},
esc: {..}}, rounds: [{round, new_material, new_total, dead_slots}]}`. Coverage is **never** reported as
"percent complete": in the simulation it read 0.976 when 83% had been found (`unseen-estimation.md` §2.3).

**trace.json**: typed edges `{from, to, type: supports|depends|implements|rejects}` over premises,
probes, decisions, rows, plan items and findings, plus `unmapped: []`, which must be empty.

**residual.json**
```json
{ "id": "RS-3", "property": "", "why_unreachable": "production-traffic|external-tenant-not-held|elapsed-calendar-time|operator-eye",
  "closest_probe": "P-..", "verification_cmd": "", "owner": "agent|operator", "due": "YYYY-MM-DD",
  "backlog_id": "", "falsifier": "", "reopens_on_fail": ["AC-.."] }
```

**verdicts.jsonl**:
`{at, kind: phase-gate|final-gate|reask|extend|build-start, frame_sha, snapshot_sha, harness_probe,
vector: {V1..V10}, gate: {G1..G12}, answer: yes|no|unknown, signed: signoff id|null}`.
**changes.jsonl**:
`{id, at, artifact, span, cause: operator|miss|drift|residual, hole_or_decision, delta_round}`.
**budget.json**: `{forecast: {phase: {work_h, wall_h, basis}}, actual: {..}, dial_quotes: [..],
overrun_packets: [..]}`.

---

## 6. The exit gate: exact, computed criteria

`cc-research gate --program <id>` prints one row per criterion (`G<n> PASS|FAIL <evidence>`) and exits
non-zero on any FAIL. `--phase Pn` evaluates that phase's subset. Every predicate reads the ledger and
re-executes what it names in this run.

| Gate | Predicate (all must hold) |
|---|---|
| **G1 frame ratified and falsifiable** | `sha256(frame.json)` equals the hash pinned by `cc-signoff`. Every axis is `in`, or `excluded` with a quote. The superlative lint finds 0 predicates without a number. Every historical re-ask frame maps to an axis or exclusion |
| **G2 census complete** | Every population required by an in-scope axis has a census. Its `generating_cmds`, re-run now, reproduce the member set (any diff is dispositioned). `cross_check_diff` is empty. Every decision's options include do-nothing and use-what-exists. Every grid census (hazard grid, state × input grid) has 0 empty cells: each holds a scenario with a probe, or an `na_reason`. Every `external_sources` entry is `in` with an access command, or `excluded` with a quote |
| **G3 premises at tier** | Load-bearing premises with `achieved_tier < required_tier`: 0. Premises with verdict `unknown`: 0. Every refuted premise's dependents show REVISED in `trace.json`. The refutation rate is reported; if it is 0 across ≥ `refutation_resample_min_premises` risky premises, a critic's 20% re-sample of probe falsifiers is on file |
| **G4 contact complete** | Every environment in the environment census is crossed by at least one `skeleton`, `dry-run-deploy` or `measure` probe carrying that env id. Every E5 row ran on its env with n ≥ `meas_n_min`, and with a load control when it is a timing metric. Every handed command was executed by the agent with stdin at `/dev/null` (or `--dry-run`) and its exit captured. Every scheduled component has at least one *scheduler-initiated* run observed. **Contact matrix:** every applicable cell (component × H1-H7) holds an executed probe with status `clean`, or a set-decision record (H6), or a `residual.json` entry. Every `n/a` has a reason the P1 critic did not reject. Every H1 cell's property list includes at least one liveness property. Every E4/E5 probe has `negative_control.ran=true`, or a stated reason |
| **G5 executable spec sound** | In this run, `harness.sh --self-test` exits non-zero over known-bad *and* `--self-test-green` exits 0 over known-good. Rows whose soundness is not SOUND (other than labeled regression guards): 0. Every row has a red-proof probe for its control |
| **G6 decisions ruled** | Open decisions: 0. Every *point* decision's surviving options have probes, and `what_would_flip` has been checked against probe data. Every *set* decision has 2-4 members with feasibility probes, a dated narrowing probe in build wave 1, a branch per member, a revision budget, and a `why_not_now` from the residual classes. Decisions settled by default are registered and ruled |
| **G7 traceability and persistence** | `trace check` finds 0 unmapped findings. The artifacts cite 0 paths outside the repo. Every evidence path exists at the snapshot sha |
| **G8 artifact integrity** | `cc-research lint` finds 0 errors. A fresh-context `read-through` probe after the last edit found 0 material items. The snapshot is frozen, and `changes.jsonl` has no post-freeze entry without a delta round |
| **G9 certification** | T ≥ `panels_min`; families ≥ `families_min` and non-Anthropic ≥ `non_anthropic_min`, counting only panels at or above `panel_seed_recall_floor` (otherwise the verdict prints "degraded: N families"). Every matrix candidate is dispositioned `real` or `false` by a probe or a primary read. The final matrix has 0 dead or partial slots: a dead slot is re-run, or the gate fails (the harm: three dead critics read as "no gaps", hole 189). `chao2_bc − S_obs` (material) < `unseen_material_max`. The JK2 residual ≤ `jk2_residual_max`. Representative-seed recall ≥ its minimum with n ≥ `seed_rep_n`. Escape-seed recall ≥ its minimum. The last delta round found 0 new material items. Rounds ≤ `round_cap`. The re-ask rehearsal found 0 material in-frame misses and 0 unmapped frames |
| **G10 freshness** | `premise due` is empty after re-runs. Trunk and sibling activity were read at gate time (a `git log <validated_sha>..origin/main -- <depends_on_paths>` check, plus a live-owner check on the topic). Credentials remain valid beyond the build window. External facts (registry versions, vendor pages) were re-checked within their TTL |
| **G11 residual declared** | Every hole typed `declared-residual`, and every row whose env is unreachable, is in `residual.json`. Each entry has a `why_unreachable` from the allowed list, a closest probe already run, a verification command, an owner, a due date and a backlog id (with a falsifier). `probe-kit doctor` confirms the env is *not* locally emulable |
| G12 budget reconciled (informational) | Actual against forecast is recorded, and overrun packets are resolved. G12 never blocks |

Then the operator signs with `cc-signoff`, a signed verdict row is appended, and build waves may fire.

---

## 7. The re-ask protocol: answering "are we 100.00/100.00 complete?" after the gate

**The answer is computed, never regenerated.** It is idempotent: an unchanged world yields the same
words. It is a *vector* over the operator's own frames, so a frame shift cannot relabel a known item as
a new hole (C1).

`cc-research verdict --render`:
- re-executes the harness (and any drifted premise probes);
- reads the ledger;
- renders the following. Its first line is the answer.

```
Research: YES — 100.00% of the frame you signed on 10-12 (70/70 rows sound, re-run just now; 11/12 decisions ruled, 1 carried as a signed set; 0 drift).
Contact: 41/41 applicable reality checks executed and clean; 1 choice carried as a set (sync backend, narrowed by the first build wave on 10-15, both branches pre-written).
Sources: complete against the 14 sources you signed (repo, trunk, issue tracker, access logs, public mirror, …); a new source would be a frame change.
Certified: est. unseen decision-changing holes < 0.6 (Chao2 lower bound; 7 blind panels, 3 model families); seed recall 28/30, past-escape recall 9/10.
Residual, scheduled (not open): RUM on real traffic (you, 10-20) · weekly trust roll (agent, 10-17) · corporate-tenant install (you, 10-14).
Built 0/70 · Deployed 0 · Live-verified 0 · Optimum: 3/3 ceilings measured, 2/3 met.
Since your signature: 2 holes (1 relabel of RS-2, 1 refinement → build backlog); 0 rows reopened.
No new critique was generated for this answer. To spend more search: cc-research extend --panels 6 (expected new decision-changing holes 0.4; about 3 h).
```

**Mechanics:**
1. **UserPromptSubmit hook `hooks/research-reask.sh`.** It fires only when the repo has an active
   program pointer and the prompt matches the completeness-ask patterns, a regex built from the 88
   historical asks. It injects the rendered verdict and this instruction: answer from the verdict. If
   you believe something is missing, first run `cc-research hole add` with a locus, the id it would flip,
   a frame type and a reproduction probe.
2. **Symmetric evidence burden**, a new `completion-assert.sh` arm. Anti-churn prompting alone causes
   false closure (F7), so both directions carry a burden. While a signed verdict exists, a reply to a
   completeness ask:
   - may say "yes" only if a verdict row from *this turn* shows PASS;
   - may say "no" only if it cites a hole id added this turn (material, and reproduced or pending
     reproduction) or a failing verdict row from this turn.

   Anything else is blocked with the reason "that would be a regeneration; cite a ledger row".
3. **Frames outside the ratified frame are named as expansions, not misses.** Example: "Nothing can beat
   it is outside the signed frame for metric X. Adding a ceiling row is an expansion: about 1.5 days
   (3 ceiling probes plus 1 delta round). Filed as decision D-19." It is typed C2n, cause=operator.
4. **Repeat in the same session.** An identical ask after a signed yes re-renders the same verdict,
   marked "unchanged since HH:MM". It never re-derives, because "Are you sure?" flips answers 46% of the
   time (FlipFlop, `llm-failure-modes.md` F6).
5. **`extend` is the only way to search more after the gate.** It runs blind panels on the frozen
   snapshot as additional capture occasions. It states the expected yield first (`next_panel_expected`
   and `m_g`), types every finding, and updates the estimator. The operator buys more search at a quoted
   price instead of provoking it by asking.

---

## 8. A hole after the gate: scoped, typed, never a global reopen

| Type | Test | Route | Counts as a take-back? | Reopen scope |
|---|---|---|---|---|
| Relabel (C1) | already in the ledger, residual or backlog | answer by citing the row | no | none |
| Refinement | fails M1-M5 | `cc-backlog add` into a build wave | no | none |
| Declared residual realized (C9) | row in `residual.json` | run its verification in its slot; a failure reopens its dependents | no (budgeted) | dependents |
| Drift (C10) | the recheck differs after `validated_at` | re-run the probe; outside tolerance means a scoped reopen | no (drift is counted separately) | dependents |
| Operator expansion (C2n) | new scope, cause=operator | a `Scope (grown, cause=operator)` change record, a mini-frame and a budget quote *before* acceptance (the baseline presumption against change); a descope option is quoted alongside | no | new rows only |
| Set narrowing (H6) | a carried set decision's narrowing probe ran | apply the winning member's pre-written branch; charge the revision budget | no (planned) | the losing members' branch items |
| **Material in-frame miss** (C2u, C3-C8, C11) | passes M1-M5 with a locus, and is reproduced | scoped reopen; escape record; harvested into the seed library; gate post-mortem ("which G should have caught this?") | **yes, counted** | dependency closure |
| Self-inflicted after freeze (C7) | an edit with no delta verification | revert, or delta-verify; recorded as a process defect | yes, counted | touched spans |

**The scoped reopen algorithm:**
1. Compute the transitive dependents of the hole's locus from `trace.json`.
2. Mark those rows and decisions REOPENED, citing the hole id.
3. Re-run only their probes.
4. Run one blind delta round (T ≥ 4) on the affected spans.
5. The operator re-signs only the changed artifacts. The content pin reopens only changed bytes.

Build waves that do not depend on the reopened set keep running. The verdict vector shows, for example,
"67/70 rows (3 reopened by HR-017, ETA 10-16)". (Hole records are `HR-nnn` so they cannot be confused
with the contact classes H1-H7.)

**Severity decides blocking; type decides counting.** Every post-gate hole also gets the §3.8 severity
class:
- only `significant` stops build waves inside its dependency closure;
- `functional` reopens that closure while unrelated waves continue;
- `process` and `lifecycle-data` stay open with a justification and are never a reason to reopen.

This is how aviation certification ships with open problem reports without re-litigating the baseline
(EASA AMC 20-189, `systems-engineering.md` §3). The reopen stays local because every row traces to a
premise, a decision and a source, just as every STPA result traces to a loss (STPA Handbook p.16).

**Error budget.** The method's own target is at most 1 material in-frame escape per program, against a
historical baseline of about 1.1 decision-changing holes *per re-ask*. Each program's
`verdicts.jsonl` and post-gate `holes.jsonl` produce a method report: escapes per phase and gate. It is
the self-audit the operator is actually asking for.

---

## 9. Budget and time model: a predictable forecast

### 9.1 Cost classes

These are priors: estimates to calibrate, not measurements, except where a receipt is named.

| Unit | Prior (active hours) | Basis |
|---|---|---|
| E2 read probe | 0.1-0.25 | estimate (one command) |
| E3 live read | 0.25-0.5 | estimate |
| E4 measurement (n ≥ 5, load control) | 1-3 | FLEET_V2 W0: about 9 measurement items in about one day (plan log `LIMIT_RECOVER_FLEET_V2.md:575-590`, estimated) |
| E5 target-env probe | 2-6 | estimate (launchd, container build, tenant call) |
| Contact skeleton | 8-16 | estimate |
| Model check or stateful property test | 4-8 each, including tool setup | estimate (TLC and `hypothesis` are not installed, §10.3) |
| Fault injection | 1-3 per applicable hazard-grid cell | estimate |
| Load run on the skeleton (H2 cell) | 2-4 | estimate |
| Deploy plus rollback rehearsal (H7 cell) | 3-6 | estimate |
| Probe-kit bootstrap (first program only) | 4-8 agent, plus operator approval of installs | estimate: Java runtime and TLC, `pip install hypothesis`, a Docker daemon that answers `docker info` (§10.3) |
| Census | 0.5-1.5 per population | estimate |
| Option probe (spike) | 1-4 | estimate |
| Acceptance row plus control | 0.2-0.5 | DOCS §9 audited 58 commands and built the harness inside a 25.75 h programme (estimated share) |
| Certification round | about 1 h wall for panels (parallel), plus 3-5 h adjudication and reproduction | estimate |
| Seed authoring | 2-4 per 40 seeds | estimate |
| Operator slots | intake 60-90 min · 5 min per decision packet · signoff 15 min | estimate; each slot is dated in `budget.json` |

**Parallelism p ≈ 6-8** concurrent units: 4 accounts, with `cc-wave-plan` capping each account at 2 per
wave (`bin/cc-wave-plan` header: "≤ CC_WAVE_MAX_PER_ACCT (default 2) items/account/wave"). The formula:

`Wall(phase) = max(critical_path, Σ unit_cost / p) + dated operator waits`

`Forecast = Σ Wall(phase) × (1 + c)`, where the contingency c starts at 0.30 and is calibrated per
program.

**Probe ordering is what keeps the allowed loops short.** Inside P2-P4 the probe queue is ordered by
expected information per hour, not by document order:

`priority = p(refute) × dependents × late_cost / probe_cost`

- `p(refute)` starts from the historical base rate for the premise's *origin* tier. An E1-origin
  premise gets about 0.27, the false-when-written share of plan moves (`plan-lifecycle.md` §3).
  Calibration refines it.
- `dependents` is the premise's fan-out in `trace.json`.
- `late_cost` is the cost class of discovering it after build: its §1.4 contact class.

Refutations then arrive while few decisions rest on them, so the P2/P4 → P3 re-plans are small and
bounded. The formula is expected loss avoided per hour of probing, which is Howard's value of
information (Howard 1966, `stopping-rules.md` row D1). It agrees with Reinertsen, "we create economic value when the benefit
of the created information exceeds the cost of creating it", and with Boehm, "the level of risk incurred
by not doing enough" (`epistemic-limits.md` §1.3-1.4). A premise everyone is sure of gets a low
p(refute), so its probe runs later, but it is never skipped.

Ordering never exempts a load-bearing premise from its tier. It decides only *when* each probe runs and
at what n.

### 9.2 Worked example: a medium greenfield ("weeks")

Inputs: 16 axes (12 in scope), 14 census populations of the 16 types (including the external-source
census and the hazard grid), 60 risky premises (30 at E2, 12 at E3, 10 at E4, 8 at E5), 12 decisions averaging 3.5
surviving options (42 option probes; 2 decisions carried as sets), 70 acceptance rows, a skeleton
crossing 6 boundaries, 2 state machines, 6 components in the contact matrix, a hazard grid of 8 control
actions × 4 unsafe types (16 applicable cells), 3 H2 load cells, 2 H7 rehearsal cells, 7 panels, and
30 + 10 seeds. p = 6.

| Phase | Work (h) | Wall |
|---|---|---|
| P0 | 6 agent + 1.5 operator | 1.0 d (includes the operator slot) |
| P1 | 14×1 + 4 = 18 | 0.5 d |
| P2 | 30×0.2 + 12×0.4 + 10×2 + 8×4 = 62.8 → 10.5 h wall; the longest E5 probe is about 6 h | 1.5 d |
| P3 | 42×2 + 4 = 88 → 14.7 h wall | 2.0 d |
| P4 | 70×0.35 + 12 (skeleton) + 2×6 (model checks) + 16×2 (hazard-grid faults) + 3×3 (load) + 2×4 (deploy rehearsal) = 97.5 → 16.3 h wall; the skeleton on the critical path is 12-16 h | 2.5 d |
| P5 | 6 | 0.75 d |
| P6 | seeds 3 + round 1 (1 + 4) + integration 2 + delta 1 (3) + delta 2 (3) + rehearsal 2 | 2.0 d |
| P7 | 1 + operator signoff | 0.25 d |
| **Total** | | **≈10.5 d; with c = 0.30, a forecast of 10.5-14 working days** (first program on this machine: add 0.5-1 d for the probe-kit bootstrap) |

Receipt for the arithmetic: 1.0 + 0.5 + 1.5 + 2.0 + 2.5 + 0.75 + 2.0 + 0.25 = 10.5, and 10.5 × 1.3 = 13.65.
The hour figures are priors (§9.1); only the structure is a claim.

Comparison: past research phases took 1-2 days (`greenfield-cases.md` case table) and then leaked for
weeks. LIMIT_RECOVER_100P spent 22 days and 30 goals after "complete" (`plan-lifecycle.md` §4.1). RCF
deliberately spends more before the claim and much less after it. External evidence points the same
way: GAO found that programs which changed requirements after development began saw 72% cost growth,
against 11% for those that did not (`systems-engineering.md` §6, statute page). That is the price of
discovering the frame late.

### 9.3 The perfection dial, priced in advance

The operator is willing to spend "100x for 1%", so the method *quotes* that price rather than
discovering it one hole at a time. Using the worked estimator (`unseen-estimation.md` §3.6: 8 panels,
S_obs 47, Ŝ ≈ 56):

| Target (fraction of Ŝ) | Extra panels |
|---|---|
| 90% | 3.1 |
| 95% | 7.6 |
| 99% | 18 |
| asymptote (expected unseen < 0.5) | 34 |

At 7 panels per round (about 1 h wall plus about 4 h adjudication), 99% adds about 1.5 days and the
asymptote about 2.5-3 days.

A seed-recall certificate of a 1% or lower miss rate at 95% needs 300 seeds, all found (rule of three).
That is about 20-40 authoring hours, so about 3-5 more days.

The operator picks the dial at P0 and can raise it later with `extend`. Either way the cost is stated
first. Overshoot is the dominant excess cost in certified recall (Lewis 2021,
`stopping-rules.md` B3), so the default dial is 95% of Ŝ with seed recall of at least 0.90.

### 9.4 Overrun and calibration

- **Overrun.** When any phase reaches 1.5x its forecast, a class C packet opens with the conviction
  and a receipt. It offers three options: extend by X (with the reason), move axis Y to residual, or
  accept the current certificate. A budget never extends silently: the forecast is a forecast, and the
  gates are the stop.
- **Calendar against active time.** Operator slots and residual owners carry dates, so dormant time is
  visible and not mistaken for unfinished research. In the sevenrooms case, 33 of 35 days were idle
  (`greenfield-cases.md` mechanism 9).
- **Calibration.** After each program, actual unit costs, round counts and post-gate escapes update the
  priors in a shared `docs/research/rcf-calibration.jsonl`. The contingency c shrinks as programs
  accumulate.

---

## 10. Mapping to this environment: what to build

### 10.1 New components

| # | Build | Where | Addresses |
|---|---|---|---|
| B1 | **`bin/cc-research`** (Python). Subcommands: `init` (scaffold plus topic lock); `frame {new,lint}`; `census {add,verify,grid}`; **`contact {init,check}`** (builds `contact_matrix.json` from frame components × H1-H7; `check` fails on an empty applicable cell); `premise {add,due,queue}` (`queue` prints the §9.1 priority order); **`probe run`** (wraps the command; records env descriptor, sha, stdin, n, raw output and exit; runs the negative control where declared; refuses `mutates_live` without `--sandbox`; computes tiers); `decision {point,set,narrow}`; `harness selftest`; `trace check`; `lint`; `freeze`; `seed {plant,library}`; `panel collect`; `adjudicate`; `estimate` (Chao2 bias-corrected, JK1/JK2, coverage, q0, `m_g`, per-family, seed recall with rule-of-three bounds); **`gate`**; **`verdict`**; `extend`; `hole {add,type,reopen}`; `budget {forecast,actual}` | `claude-infrastructure/bin/` | all; the tool is the ledger's only writer |
| B2 | A **`research-program` skill plus `/research-program` command** that drives P0-P7. It includes the intake question set, the 16-axis template and the materiality rule. The existing `/research` stays as the wave primitive inside P1 and P3 | `skills/`, `commands/` | C1, C2, C11 |
| B3 | **Workflows** under `~/.claude/workflows/`: `research-contact.mjs` (one `workflow-lean` slot per probe; schema'd return `{probe_id, exit, raw_path, verdict, measured}`); `research-certify.mjs` (seeded snapshot; cross-family panels, with Opus and Fable as agent slots and Bash slots calling `codex exec` and `ollama run <model>`; panel admission by seed recall; the reproduce-or-read adjudicator stage; the estimator stage; a dead slot fails the run); `research-rehearsal.mjs` (the 12 re-ask frames) | `~/.claude/workflows/` (existing: `pyramid-fans.mjs`) | C8, C9, C1 |
| B4 | **`probe-kit doctor` / `install`**: an environment census of this machine, plus operator-approved installs (`pip install hypothesis`, a Java runtime plus TLC, a Docker daemon that answers). The doctor resolves binaries with the *interactive* shell's PATH, because the agent Bash tool's PATH is `/usr/bin:/bin:/usr/sbin:/sbin` plus kitty, and there `shellcheck`, `codex` and `ollama` read as absent though they are installed (measured today). It also reports per-family panel availability and auth | part of B1 | C9 reach; C5 (a broken tool read as a negative) |
| B5 | **The seed library**: `docs/research/seed-library/escapes.jsonl`, harvested from `/tmp/rescomp/taxonomy_holes.py` (200 rows) as generic, class-stratified seed templates. Persisted in the repo | `docs/research/` | C8 hard tail, C6 |
| B6 | **`hooks/research-reask.sh`** (UserPromptSubmit), keyed on the repo's active program pointer | `hooks/` | C1 re-ask, the regeneration loop |
| B7 | **`completion-assert.sh` arms**: R1, a research-complete claim requires gate PASS at the current snapshot; R2, the symmetric verdict burden (§7) | `hooks/completion-assert.sh` | G7 asymmetry (`close-assertion.md` G7) |
| B8 | **`wrap-ledger.sh`**: add a GOAL line computed from `cc-research verdict --machine`, so two verdicts appear (the session verdict and the goal verdict). Change the absent-DoD case from ✅ to unknown | `scripts/wrap-ledger.sh:2286-2288` | C1; `close-assertion.md` G1, G3 |
| B9 | **`dod-persist.sh`**: `Scope (frozen)` may be a pointer (`program <id> frame <sha256>`); `Scope (grown)` gains a `cause=` field | `hooks/dod-persist.sh:76-96` | C1, C2 (G5 in `close-assertion.md`) |
| B10 | **A build-fire precondition**: implementation waves of a program fire only when `cc-research gate` PASSes (a `--requires-gate <program>` check in `handoff-fire.sh`, or the plan's Phase 0 goal) | `scripts/handoff-fire.sh` | C8 (hole 137) |
| B11 | **Signoff and board**: reuse `cc-signoff` and `cc-mission` for frame ratification and gate signoff. The agent advances to `awaiting-signoff` only | existing `bin/cc-signoff`, `bin/cc-mission` | C2, C11 |
| B12 | **Queue integration**: residual items go to `cc-backlog add --why-not-now "not-yet-true: …" --falsifier`; operator-only probes to `cc-backlog needs --run`; decisions below 90% to `cc-decide open --class C --conviction --receipt` | existing | C9 residual, C3 |

### 10.2 Existing text to change (proposals; this unit edits nothing)

- `agents/deep-research.md:187` "Find 2-3 gaps", `agents/research-decomposition-critic.md:37-38`
  "name 1-3 plausible axes … MISSING", and `skills/research-subagents/SKILL.md:798-803` "List 3 …
  promote 'not obviously relevant'". Replace all three with the zero-allowed wording: every item carries
  a locus and the id it would change; "zero is an expected answer".
- Move the negative-space trigger to P0 (frame critic), so the exclusion list the operator signed
  satisfies the existing "cite the user's words" exit.
- `SKILL.md:944-948`, "a re-check … apply this rule more aggressively". Inside a program, a re-check
  becomes `extend` with a quoted yield.
- OASIS (`SKILL.md:756-782`) stays the within-wave spawn heuristic. Research-program completion is
  decided only by G9. OASIS criterion 3, the `c·N^α` fit, has no asymptote and cannot state a residual
  (`unseen-estimation.md` §6).
- Follow-On Gate F1 (`CLAUDE.global.md:616-617`) gains one sentence: inside a signed program, only M1-M5
  items are net-positive for reopening. Others go to the build backlog.
- `commands/are-we-done.md:70-72`: for a program, "exhaustively" means a gate PASS re-executed this
  turn, plus the session facts.
- plan-conventions: a program's Phase 0 locus is P0 L, P1-P6 S (P2 and P6 driving Workflows), P7 L.

A dispatched-phase goal, as a single-line template:
`--goal 'P2 contact wave closed — proven by cc-research gate --program <id> --phase P2 printing G3 PASS and G4-env PASS; do not run any probe with mutates_live=true; full brief in the prompt above, frame at docs/research/<id>/frame.json'`
(`--phase P2` evaluates only the environment rows of G4. The contact-matrix rows of G4 belong to P4's
sub-gate.)

- `skills/ground-up/SKILL.md:14-18` (superlatives banned from the DoD) becomes the I6 lint inside
  `/research-program`. It is the one place the repo already names this loop's root cause.

### 10.3 Probe-kit facts on this machine today (P0 must re-verify them)

Re-measured 2026-09-30 after the 15:26 reboot:
- `/bin/bash --version` => `GNU bash, version 3.2.57(1)-release (arm64-apple-darwin24)`. This is the
  launchd interpreter (hole 92).
- `sw_vers -productVersion` => `15.7.9`.
- `/opt/homebrew/bin/timeout 10 /usr/local/bin/docker info --format '{{.ServerVersion}}'` => the CLI
  panicked (`reflect: indirection through nil pointer to embedded struct`). The daemon's state is
  therefore unverified, so Linux-image probes (hole 95) are not yet available locally.
- `/usr/bin/java -version` => "Unable to locate a Java Runtime", so TLC is unavailable.
- `python3 -c 'import hypothesis'` => `ModuleNotFoundError`.
- Present by absolute path: `/opt/homebrew/bin/shellcheck`, `/opt/homebrew/bin/bats`
  (`-> ../Cellar/bats-core/1.13.0/bin/bats`), and `/opt/homebrew/bin/timeout` and `gtimeout`. A
  command-rewrite hook turned a first check of the bare word `bats` into `~/.claude/bin/cc-bats`. That
  is another reason the doctor must record the resolved path it actually executed.
- `~/.local/bin/codex`: `codex login status` => `Logged in using ChatGPT`; `codex-cli 0.147.0`.
- `/opt/homebrew/bin/ollama list` => gemma4:26b-a4b-it-qat, qwen3-coder:30b-gguf-unsloth,
  devstral:24b, laguna-xs-2.1, qwen3:8b and smaller.
- `gemini`, `pi` and `grok` are **not installed**: `whence -p` under login and interactive zsh found
  none, and neither did `find` over `~/.local ~/.bun ~/.npm-global /usr/local/bin /opt/homebrew/bin`.
- **PATH trap:** the agent Bash tool's PATH is `/Applications/kitty.app/Contents/MacOS:/usr/bin:/bin:/usr/sbin:/sbin`.
  A bare `command -v shellcheck codex ollama` there prints nothing even though all three are installed.
  A probe that trusted it would record three false negatives (the C5 "broken tool read as a negative"
  shape; memory `interactive-grep-is-ugrep-not-usr-bin-grep.md`).

**Consequence for the dial.** Three families are reachable today: Anthropic, OpenAI and local
open-weight. The third counts only if a local model clears the seed-recall floor. Until the doctor
passes, a certificate that cannot field 3 admitted families, or a Linux-image probe, or a model check,
**degrades explicitly**: the verdict names what is missing. It never claims silently.

---

## 11. Taxonomy coverage: every class addressed or declared residual

| Class | RCF mechanism | Gate | What remains |
|---|---|---|---|
| **C1** claim frame narrower than the question (23) | A verdict *vector* over the operator's own frames. A computed follow-on line built by reconciling every store. Re-asks answered from the ledger. Relabels typed. The re-ask rehearsal runs before signoff | G1 (frame map), G9 (rehearsal), §7 | None inside the frame. A frame the operator newly names becomes a typed expansion |
| **C2** operator intent late (12) | C2u: mine the history first (`msg`, transcripts, `cc-decide`, house rules), the 12-question interview, an E6 operator-contact prototype (the H5 cell), operator co-signature. C2n: `Scope(grown, cause=operator)`, a mini-frame, an impact quote and a descope option *before* acceptance (baseline plus presumption against change) | G1 | **C2n is declared residual** (legitimate growth, 3%); C2u is reduced, not zero |
| **C3** unverified premise (29) | A premise register with *computed* tiers. Load-bearing premises must reach E2-E5 through `probe run`. Inherited figures stay at E1 until re-probed | G3, G10 | None above tier; a tolerance miss becomes drift |
| **C4** population never enumerated (32) | Up to 16 census population types (§3 P1), each with a generating command, an independent cross-check and a coverage argument. Two are *grids* whose empty cells are visible: the STPA hazard grid and the state × input grid. There is an external-source census, and the contact matrix itself is a census. Options always include do-nothing and use-what-exists. Fable and a non-Anthropic critic read the census | G2, G4, G6 | Unknown populations: bounded by estimators and omission seeds, never proven absent. Completeness is stated relative to the signed source list (Zowghi and Gervasi), so a new source is a typed frame change |
| **C5** instrument could not discriminate (29) | Every row shown red on a planted defect. Harness self-test red and green. n ≥ 5 with a load control. A production-payload harness. Re-execution instead of recall. Reproduce-first for holes. Negative controls on E4/E5 probes, plus a refutation-rate check on the probe set. `probe-kit doctor` resolves real binary paths (the PATH trap, §10.3) | G5, G4, G3 | None for gated rows |
| **C6** research did not reach the artifact (12) | A prior-art sweep at P0/P1, the trace check, repo-only evidence, a topic lock with a positive owner signal, and prior findings imported as E1 premises | G7 | None mechanical; the index is only as good as `cc-memory-search` and transcript reach |
| **C7** hole from the session's own edits (10) | A single integrator, integrate-not-append, a consistency lint, a recorded fresh read-through after the last edit, freeze, and deleting machinery rather than patching it. Delta rounds are limited to touched spans, and they *re-execute* the touched probes and model checks, because a fix is a design too (AWS: "a bug in the first proposed fix") | G8, G9 | Post-freeze edits are counted as a process defect |
| **C8** review late or unsaturated (8) | Certification before any claim, a dead slot blocks, a round cap of 3, estimator stopping, candidates settled real or false by probe or read before they are counted, and build fire gated on PASS | G9, B10 | A certificate is a lower bound (correlated panels) |
| **C9** contact-only (30) | Contact Wave W0 ordered by expected information. The H1-H7 contact matrix with an executed probe in every applicable cell: model check (H1), load on the skeleton (H2), real-dependency spike (H3), skeleton end to end on every boundary with scheduler-initiated runs (H4), operator prototype (H5), set decisions (H6), deploy and rollback rehearsal (H7). Real artifacts, synthetic production-scale rigs, time-compressed TTL probes, and every handed command run by the agent | G4, G6, G11 | **Declared residual**: production traffic, external tenants not held, elapsed calendar time and the operator's eye (6 of 30 historically: holes 16, 34, 95, 121, 134, 170), each scheduled with an owner and a date. Where the deciding fact lives there, the decision is carried as a set, not guessed |
| **C10** reality moved (8) | Validity stamps (sha, TTL, recheck command). Trunk and sibling re-reads before every recommendation (P3) as well as at the gate and at build start. Credential re-reads. The no-mutation probe policy | G10, build-start verdict | **Declared residual**: drift after the gate (4 of 8 were unforeseeable: holes 5, 46, 49, 103), handled as typed revalidation, never a take-back |
| **C11** criterion never operationalized (7) | The superlative lint (the superlative appears in 80 of 88 historical completeness asks, §3 I5), ceilings measured first, a positive reference set with the operator's eye as a named E6 gate, pre-registered thresholds and negative-result branches, and holds with expiry dates | G1, G5 | Taste stays operator-judged by design |

---

## 12. Residual risk (honest limits)

1. **Universal blind spots.** Holes that every model family misses are invisible to any overlap
   statistic (Link 2003). Seeds and contact probes shrink this set, but the certificate stays a *lower
   bound*.
2. **Correlated panels bias the estimates low.** This is measured for multiple-choice errors (Kim 2025)
   but unmeasured for design-hole finding. The first program must record the family × family overlap
   matrix to calibrate it.
3. **Seed realism.** Synthetic seeds are easier to find (Musa), and mutants miss 27% of real faults
   (Just 2014). The escape library helps, but it is not a full sample of future escape types.
4. **The irreducible contact residual** is production traffic, external tenants not held, elapsed time
   and taste. It is declared and scheduled, not eliminated.
5. **C2u and C2n.** The interview and history mining reduce unelicited intent, but cannot remove it.
   Genuinely new requirements remain, and they are typed.
6. **Drift after the gate** is typed and re-validated. It still costs time.
7. **Classifying materiality is a judgment.** The "uncatchable" bucket in the TM2 case moved from 13 to
   5 with its definition. Naming an id, using two adjudicators, and treating disagreement as material all
   narrow it, but none of them eliminates it.
8. **The method can create its own machinery holes** (C7 applied to RCF). Mitigations: it is code with
   tests, the artifacts are templated, and the first program is an explicit calibration run.
9. **The budget priors are estimates.** Only W0 and DOCS §9 anchor them. Expect the first 1-2 programs
   to recalibrate c.
10. **Tooling gaps today (re-measured after the reboot, §10.3).** The Docker daemon cannot be read (the
    CLI panics), Java/TLC and `hypothesis` are absent, and `gemini` and `pi` are not installed. Until
    `probe-kit doctor` passes, the certificate degrades, and it says so.
11. **The third family may not qualify.** The only non-Anthropic families on hand are OpenAI (`codex`)
    and local open-weight models of 24-30B (`ollama`). Whether any local model clears the seed-recall
    floor as a design reviewer is unmeasured. If none does, the certificate runs on 2 admitted families
    and says "degraded". Buying a third cloud family (reinstalling `gemini`, for example) is a
    `cc-backlog needs` step for the operator, not something this design can assume.
12. **Set decisions could become an escape hatch.** An agent could label a hard decision a "set" to
    avoid ruling on it. Three things limit this: `why_not_now` must be one of the four residual classes,
    every member needs a feasibility probe, and the P1 critic and the gate read the set records.
    Judgment remains.
13. **Contact-matrix `n/a` cells are judgment.** A wrongly excused cell is a C4 miss in a new place. The
    critic reads the reasons, and the escape library should gain seeds of the form "H7 marked n/a for a
    component that deploys". That still does not make the matrix proof against a shared blind spot.
14. **The H1-H7 classes are a synthesis of sources, not a standard.** Several receipts behind them are
    secondary (the Mars Polar Lander report, Brooks and the Toyota principles via snippets;
    `epistemic-limits.md` §4). The grid's columns may need an eighth class after the first programs.

---

## 13. Adversarial self-check of this design

- **"Your angle's premise is overstated: 64.5% of holes were desk-findable."** Accepted, and it is why
  §1 counts primary reads and census commands as contact, and why C1, C2, C6, C7 and C8 rely on
  structure. The claim is not "most holes need a spike". It is "no load-bearing claim may be closed
  below its evidence tier, and the tiers are climbed up front".
- **"Estimators and seeds are heavy for a plan document."** They run once, in P6, on a frozen snapshot,
  with a round cap. That costs about 2 days (§9.2), against 22 days and 30 goals of post-claim leakage
  in LIMIT_RECOVER_100P.
- **"The symmetric burden will suppress real holes."** No: a "no" is always allowed when it cites a hole
  row, and adding a hole row is always allowed. What is blocked is a *non-receipted* regeneration.
- **"Operator friction."** The operator's burden is one interview (≤12 questions), packets only for
  decisions below 90%, one frame signature and one gate signature. That is less than the 31 completeness
  asks across 270 prompts they make today (`greenfield-cases.md`).
- **"A contact wave before design is premature: you cannot know what to probe until you have
  designed."** Only half of it runs before design. W0 probes what exists before any design: the
  incumbent, the environments, the ceilings, and premises inherited from docs and memory. Boehm puts
  risk resolution first for exactly this reason (`epistemic-limits.md` §1.4). Design-dependent contact
  (option spikes, the skeleton, model checks) runs in P3-P4, after the options exist but before
  anything is signed. The positive control is FLEET_V2: W0 measurement first reshaped the design, and
  W0-W6 then landed in about 1.5 days.
- **"Set decisions are take-backs by another name."** A take-back reverses a signed claim and costs an
  unplanned re-plan. A set narrowing executes a branch that was written, priced and signed *before* the
  gate. The operator sees the set and its narrowing date in the verdict render, so it is never presented
  as settled when it is not. What is forbidden is the historical pattern: a point decision presented as
  settled and then reversed by contact (holes 110, 119, 181).
- **"Reinertsen says the best tests fail half the time, but your gate wants everything green."** The
  gate requires every probe to be *executed and dispositioned*, not to pass. Refutations are expected
  and flow forward (P2 → P3). A W0 with a 0% refutation rate over at least 20 risky premises is itself
  flagged for review (§3 P2).

## 14. Receipts index

- Taxonomy and ledger: `/tmp/rescomp/taxonomy.md`, `/tmp/rescomp/taxonomy_holes.py`, and
  `python3 /tmp/rescomp/taxonomy_stats.py`.
- Hole-id lookups: `/tmp/rescomp/design/.ledger_dump.txt` (one line per ledger row, generated from
  `taxonomy_holes.py`); shard-7 H-ids from `/tmp/rescomp/forensics/shard-7.md:135-155`.
- The operator's re-ask frames: `/tmp/rescomp/loop_asks.json` (88 asks), counted by
  `python3 /tmp/rescomp/design/reask_frames.py`.
- Positive controls:
  - reso `docs/plans/DOCS_CONSOLIDATION_100P.md:2059-2099`;
  - `docs/plans/LIMIT_RECOVER_FLEET_V2.md:148` (the `10,25,40` placeholder), `:158-171` (W0 brief) and
    `:575-590` (W0 results; the "5-6 concurrent requests" quote is `:581`);
  - `skills/ground-up/SKILL.md:14-22`.
- Machinery anchors (all verified this session):
  - `scripts/wrap-ledger.sh:616-623, 2286-2288`;
  - `commands/are-we-done.md:52-57, 70-72`;
  - `hooks/dod-persist.sh:1-16`;
  - `skills/research-subagents/SKILL.md:756-830`;
  - `agents/deep-research.md:180-190`;
  - `skills/frontier-run/SKILL.md:136`;
  - `bin/cc-signoff:1-30`;
  - `bin/cc-wave-plan` header;
  - `agents/workflow-lean.md`;
  - `~/.claude/workflows/pyramid-fans.mjs`.
- External sources: `/tmp/rescomp/external/stopping-rules.md`, `unseen-estimation.md`,
  `llm-failure-modes.md`, `epistemic-limits.md` (Cynefin; AWS TLA+ pp.1, 3, 5, 7, 11; Boehm pp.3, 5, 9;
  Reinertsen; Toyota SBCE; Brooks; XP spike; FDA 820.30; Knight Capital; the H1-H7 table) and
  `systems-engineering.md` (NPR 7123.1D App. G; NASA SEH 6.2 and 6.5; AMC 20-189; STPA Handbook
  pp.16-39; Zowghi and Gervasi via arXiv:2308.03784; FY2009 NDAA §814 and the GAO 72%/11% quote), with
  their primary citations.
- Machine facts (§10.3) were re-measured 2026-09-30 after the reboot with the commands quoted there.

## Revision log

- **2026-09-30, first version** (before the 15:26 CDT reboot). §0-§14 as designed from the taxonomy,
  forensics, internal audits and three external reports.
- **2026-09-30, post-reboot revision** (this unit, re-run by the workflow). Integrated with Edit; no
  section was removed.
  - **Receipts.** Remapped about 40 hole citations that used shard-local ids ("31a", "47a", "53a",
    "H8") or pointed at the wrong ledger row ("hole 73" for Parakeet Unified, which is #173; "hole 43"
    for CAP 5000, which is #115; "hole 59" for the `!` shell, which is #155). Every citation now uses
    ledger ids 1-200. Class counts (C1-C11 = 23/12/29/32/29/12/10/8/30/8/7; the contact-class subtotal
    135 with 65 DC) were re-verified against `python3 /tmp/rescomp/taxonomy_stats.py`.
  - **New evidence integrated** from `epistemic-limits.md` and `systems-engineering.md`: §1.4 contact
    matrix (H1-H7); the complicated-vs-contact sort; probe ordering by expected information (§9.1);
    set decisions (P3, G6, schemas); grid censuses (STPA hazard grid, state × input grid); re-running
    the same instrument on every fix; the external-source census and source-relative completeness (§2);
    the frame as a baseline with a presumption against change and a descope channel; AMC 20-189
    severity classes for post-gate holes (§3.8, §8); the GAO cost-growth evidence (§0, §9.2).
  - **Corrected machine facts:** `gemini` and `pi` are not installed. The families are Anthropic,
    OpenAI (`codex`, logged in) and local `ollama` models. Added the panel-admission floor, the PATH
    trap, and bats resolving to bats-core.
  - **P6 change:** every candidate is settled real or false by a probe or a primary read before it is
    counted. Cross-family agreement only prioritizes.
  - **Budget:** the worked example was re-computed with the new grid, load and rehearsal cells
    (10.5-14 working days, plus 0.5-1 d bootstrap on the first program).
  - **Re-ask frame table** rebuilt as a script (`reask_frames.py`); the new catchphrase row reads 80 of
    88.
