# How high-assurance engineering makes an upfront phase terminate

Status: COMPLETE. Research date 2026-09-30. About 32 web calls (counted by hand from this
session's tool calls), 18 source rows. Gaps: no Definition of Ready source; ISO 26262-8 change
management and FMEA scoping not verified; DO-178C and 29148 quoted only through secondary
sources, because the standards are paywalled.
Scope: NASA NPR 7123.1 lifecycle reviews, configuration baselines + CCB, DoD milestones,
DO-178C, ISO 26262 / STPA / FMEA completeness arguments, Davis / IEEE 29148 "complete",
Definition of Ready. Key question: "complete" relative to a DECLARED FRAME; post-baseline gap
handling (change request vs defect) so a late finding does not reopen everything.

Receipt convention: [Sn] refers to the source table at the bottom. "Quote" = text returned by
WebFetch/WebSearch summariser of the primary page (a summarising model sits between me and the
page; treat paraphrase-level wording as such where noted).

## 1. NASA NPR 7123.1D Appendix G: review entrance/success criteria

- Entrance criteria are "activities and products that are to be completed before the review can
  begin"; App G says criteria are "recommended best practices", not an exhaustive product list,
  and tailoring is expected [S1][S2].
- PDR success: preliminary design "meet[s] all technical requirements and performance measures
  or has waivers" [S2]. CDR success: detailed design meets requirements "with adequate margins" [S2].
- TBD/TBR rule (recurs across tables): "TBD and TBR items are clearly identified with acceptable
  plans and schedule for their disposition" [S2]. => Completeness at a gate is NOT "no unknowns";
  it is "every known unknown is named, owned and scheduled".
- SRR (project, Table G-4) success criterion is RELATIVE TO THE NEXT PHASE, not absolute:
  requirements "are responsive to the stakeholder needs and parent requirements, reflect the
  system's intended operational use, and represent capabilities likely to be achieved within the
  scope of the project. The maturity of the requirements definition and associated plans is
  sufficient to begin Phase B." SRR entrance: requirements "ready to be baselined after the
  review" [S2, second WebFetch].
- MDR/SDR (Table G-5) entrance: "Defined architecture, including major tradeoffs and options
  ready to be baselined after review comments are incorporated" [S2].
- G.1 is explicit that the criteria are not a closed universe: "The entrance criteria do not
  provide a complete list of all products and their required maturity levels"; customized
  criteria assess "technical maturity, planning adequacy, budget/schedule credibility, and
  readiness advancing to subsequent phases" [S2].
- NASA SEH 6.2.1.2.4: "Once the requirements have been validated and reviewed in the System
  Requirements Review (SRR) in late Phase A, they are placed under formal configuration control.
  ... Thereafter, any changes to the requirements should be approved by a Configuration Control
  Board (CCB) or equivalent authority." 6.2.1.2.5 names "requirements creep" ("requirements grow
  imperceptibly") and requires a process "that assesses the impact of the proposed changes prior
  to approval and implementation" [S7].

Interpretation (mine, not NASA's): the frame is (parent requirements + stakeholder needs +
scope of the project) and the bar is "sufficient to begin the next phase". The question "is it
100% complete?" is never asked at SRR; the question is "is it mature enough that the NEXT phase
can proceed, with every open item listed as TBD/TBR with an owner and a date?".

## 2. Configuration baselines and change control (NASA SE Handbook 6.5)

- Baseline = "an agreed-to description of attributes of a CI at a point in time and provides a
  known configuration to which changes are addressed" (SEH 6.5.1.2.2) [S3].
- Four baselines tied to reviews: Functional @ SDR, Allocated @ PDR, Product @ CDR,
  As-deployed @ ORR [S3].
- CCB disposes proposed changes to baselines; major vs minor classification; waivers release a
  project from a requirement WITHOUT changing the baseline [S3].

## 3. DO-178C

- Table A-3 HLR objectives (secondary summaries; DO-178C text is paywalled, not fetched): HLRs
  comply with system requirements, are accurate and consistent, compatible with target computer,
  verifiable, conform to standards, traceable to system requirements [S5]. Note there is no
  objective "HLRs are complete in the open world": completeness is expressed as COMPLIANCE AND
  TRACEABILITY TO THE PARENT (system requirements) plus bidirectional trace so that orphans in
  either direction are detectable [S5]. Derived requirements (not traceable up) are the escape
  valve and must be handed to the system safety assessment [S5].
- DO-178C Section 7 SCM (secondary summaries): configuration identification, baselines and
  traceability, problem reporting, change control; control-category-1 data "can only be changed
  after a release using a formal change process, which is facilitated through a Problem Report
  (PR)" [S16].
- AMC 20-189 / FAA AC 20-189 "The Management of Open Problem Reports" (EASA Easy Access Rules,
  WebFetch) [S17]: an OPR is "A problem report that has not reached the state 'Closed' at the time
  of approval". Classes: "Significant" = "actual or potential effect ... that may lead to a
  Catastrophic, Hazardous or Major failure condition, or may affect compliance with the operating
  rules"; "Functional"; "Process" = "a process non-compliance or deficiency that cannot result in
  a potential safety, nor a potential functional, effect"; "Life-cycle data" = deficiency in a
  data item not linked to a process deficiency. Rule: "OPRs classified as 'Significant' ... for
  which no sufficient mitigation or justification exists to substantiate the acceptability of
  the safety effect, should be resolved prior to approval." All others may remain open at
  approval with documented mitigations/justifications in an OPR summary.
  => This is the certification-grade answer to "we found one more small thing": a found gap is
  a CLASSIFIED ITEM IN A LEDGER, and only the top severity class blocks the gate. The rest ship
  open, recorded, justified. Finding a gap never by itself reopens the baseline.
  (Search summary adds FAA mapping: Functional -> "type 1A" if it can lead to a Minor failure
  condition, "type 1B" if No Safety Effect [S17].)

## 4. Hazard analysis completeness (STPA / ISO 26262 / FMEA)

- STPA Handbook (Leveson and Thomas, March 2018; text extracted locally with pypdf from the PDF
  WebFetch saved from flighttestsafety.org) [S14]:
  - Frame first: "Before any analysis begins, the stakeholders must identify the losses on which
    they want the analysis to focus" (p16). Every later result traces to a loss: "Because every
    STPA result will be traceable to one or more losses, the analysis results can be easily
    ranked and prioritized" (p16).
  - Bounded top level: "As a rule of thumb, if you have more than about seven to ten system-level
    hazards, consider grouping or combining hazards ... You may be including unnecessary detail
    and making the list unmanageable, difficult to review, and harder to identify things that are
    missing" (p19); checklist: "The number of hazards should be relatively small, usually no more
    than 7 to 10" (p20).
  - Completeness by enumeration over a closed grid: "There are four ways a control action can be
    unsafe: 1. Not providing ... 2. Providing ... 3. ... too early, too late, or in the wrong
    order 4. The control action lasts too long or is stopped too soon" (p36). For each control
    action in the control structure, all four cells are filled: completeness is relative to the
    control structure and the loss list, and it is mechanically checkable (empty cell = gap).
  - Late discovery is ANTICIPATED and LOCALIZED, not a reopening: "STPA is an iterative method
    and the hazards need not be set in stone at this point. Later STPA steps may uncover new
    hazards and this list can be revisited and revised as needed" (p20); "The analysis can begin
    with an incomplete control structure ... The bare minimum needed to begin the next steps is
    at least one controller, control action, and controlled process" (p31); a UCA whose effect
    matches no hazard means "you could be missing a hazard ... consider adding a new hazard"
    (p39). Because of loss->hazard->UCA traceability, a new hazard adds rows downstream of it;
    it does not invalidate unrelated rows.
- ISO 26262-3 (secondary search summaries only; standard paywalled, not fetched): the concept
  phase starts with an Item Definition whose purpose is "to define and describe the item and to
  develop an adequate understanding of it" so that each lifecycle activity can be performed; the
  item definition must be detailed enough that the HARA "can identify all relevant hazardous
  events" [S18]. => HARA completeness is declared relative to the item definition (the frame).
  NOT VERIFIED this session: ISO 26262-8 clause 8 change-management/impact-analysis wording and
  ISO 26262-3 clause 8 "modification" tailoring; treat as gaps.
- FMEA (AIAG-VDA scoping step) and DoR: NOT RESEARCHED this session (web budget spent); see
  section 6b.

## 5. Requirements completeness (IEEE 29148, Davis)

- 29148 individual requirement "complete": all information needed to understand it is included;
  "TBD" is the canonical incompleteness marker [S4].
- 29148 SET-level "complete" (secondary quotation): "The set of requirements needs no further
  amplification because it contains everything pertinent to the definition of the system or
  system element being specified. In addition, the set contains no To Be Defined (TBD), To Be
  Specified (TBS), or To Be Resolved (TBR) clauses" [S15]. Note: the frame is explicit ("the
  system or system element being specified"); and the standard's ideal (zero TBD) is stricter
  than NASA's gate practice (TBDs allowed if listed with a disposition plan, S2): the ideal is
  the end state, the gate test is "every residual TBD is enumerated and scheduled".
- IEEE 830 (the predecessor SRS standard; secondary quotations): an SRS is complete if it
  includes "definitions of all responses of the software to all realizable classes of input data
  in all realizable classes of situations" (valid and invalid inputs) [S11]. Note the frame words
  "realizable classes": completeness is over a declared partition of inputs and situations, not
  over an open world.
- Zowghi and Gervasi (Information and Software Technology 45(14), 2003, "On the interplay
  between consistency, completeness, and correctness in requirements evolution"), as quoted in
  Luitel/Hassani/Sabetzadeh arXiv:2308.03784v2 p.1 (text extracted locally with pypdf from the
  PDF WebFetch saved): "Internal completeness pertains to requirements being closed in terms of
  the functions and qualities that can be deduced solely from the requirements. ... External
  completeness focuses on ensuring that requirements encompass all the information suggested by
  external sources of knowledge ... External completeness is a relative measure since the
  external sources may themselves be incomplete, or not all relevant external sources may be
  known. While external completeness cannot be defined in absolute terms, relevant external
  sources, when available, can be useful for detecting missing requirements-related
  information." [S12]
  => This is the load-bearing theory result for the operator's complaint: "are we 100% complete?"
  asked without naming the external sources is an ill-posed question; it can only ever be
  answered "complete relative to sources {A,B,C}". Every "one more small thing" is a new external
  source being consulted for the first time.
- Jaffe, Leveson, Heimdahl, Melhart, "Software requirements analysis for real-time
  process-control systems", IEEE TSE, March 1991 (search-result summary; primary PDF at
  sunnyday.mit.edu refused connection, ECONNREFUSED): a fixed set of formal completeness criteria
  defined over an abstract state-machine model, e.g. every state has a transition for every
  possible input including timeouts; behaviour before startup, after shutdown and off-line is
  specified; all sensor information is used; transition predicates are deterministic [S13].
  => Completeness becomes CHECKABLE by fixing the model and enumerating a finite criteria list.

## 6. DoD milestones, change classes, Configuration Steering Boards

- ECP Class I vs Class II (MIL-HDBK-61A lineage, via secondary summaries): Class I = change to
  approved configuration documentation affecting functional/allocated requirements, or cost,
  warranties, contract milestones; Class II = everything else, incorporated "without customer
  approval" [S8]. A Request for Deviation authorizes departure from a requirement "for a specific
  number of units or period of time, and does not change configuration documentation" [S8].
  => Triage by blast radius: only changes that touch the baselined frame go to the board; the rest
  flow through without reopening anything.
- Configuration Steering Boards, Sec. 814 Duncan Hunter NDAA FY2009 (P.L. 110-417), statute text
  verified via `curl -sL https://wifcon.com/dodauth9/dod09_814.htm | sed ...` [S9]:
  - (c)(2)(A) CSB shall "review and approve or disapprove any proposed changes to program
    requirements or system configuration that have the potential to adversely impact program
    cost or schedule"; (B) "review and recommend proposals to reduce program requirements that
    have the potential to improve program cost or schedule" (a DESCOPE channel, not only an add
    channel).
  - (c)(5), for programs with initial Milestone B in FY2008: CSB "may not approve any proposed
    alteration ... if such an alteration would (A) increase the cost ... by more than 25 percent;
    or (B) extend the schedule for key events by more than 15 percent", unless USD(AT&L)
    certifies to Congress it is "in the best interest of the Department".
  - (e) program manager gets "the authority to object to the addition of new program
    requirements that would be inconsistent with the parameters established at Milestone B ...
    unless such requirements are approved by the appropriate Configuration Steering Board".
  - Motivating evidence quoted on the same page (GAO, March 2008): "Sixty-three percent of the
    programs we received data from had requirement changes after system development began. These
    programs encountered cost increases of 72 percent, while costs grew by 11 percent among those
    programs that did not change requirements." [S9]
- DoDI 5000.02 implementation (secondary summary): boards "are empowered to reject any changes
  and are expected to only approve those where the change is deemed critical, funds are
  identified, and schedule impacts are truly mitigated" [S10]. => a PRESUMPTION AGAINST change,
  with the burden of proof on the change.

## 6b. Definition of Ready

NOT SOURCED this session. I stopped web work at about 32 calls against a budget of about 30,
so no Definition of Ready source was fetched. Any DoR claim needs a separate lookup (Scrum
Guide, Sutherland "Ready-Ready"). What is known from sections 1-6 is enough for the synthesis:
a readiness gate is a finite checklist tied to the next phase, which makes it structurally the
same as NPR 7123.1 entrance criteria.

## 7. Synthesis: mechanisms that stop re-litigation (my inference from S1-S18; label: inferred)

M1. DECLARE THE FRAME BEFORE MEASURING COMPLETENESS. Every source defines complete relative to
    something named: parent requirements + stakeholder needs + project scope (NASA SRR, S2);
    "the system or system element being specified" (29148, S15); "realizable classes of input"
    (IEEE 830, S11); the item definition (ISO 26262, S18); stakeholder-declared losses and the
    control structure (STPA, S14); external sources consulted (Zowghi and Gervasi: "cannot be
    defined in absolute terms", S12). An unframed "are we 100% complete?" has no answer. Each
    new "one more thing" is a new external source brought into the frame for the first time.
M2. MAKE COMPLETENESS A FINITE GRID, NOT OPEN SEARCH. STPA uses control actions x 4 UCA types
    (S14). Jaffe/Leveson use a fixed criteria list over a state machine (S13). DO-178C uses
    bidirectional trace with no orphans either way (S5). Complete = every cell filled. Hunting
    for extra cells is a separate, bounded activity.
M3. THE GATE TEST IS "SUFFICIENT FOR THE NEXT PHASE" PLUS AN ENUMERATED TBD/TBR LEDGER. NASA
    SRR asks for maturity "sufficient to begin Phase B". TBD/TBR items are "clearly identified
    with acceptable plans and schedule for their disposition" (S2). Known unknowns do not block.
    Unnamed unknowns are the failure mode.
M4. BASELINE + BOARD + PRESUMPTION AGAINST CHANGE. After SRR, requirements go under formal
    configuration control. Changes need CCB approval and an impact assessment first (S7, S3).
    DoD CSBs "approve or disapprove" changes that affect cost or schedule, and the program
    manager has statutory authority "to object to the addition of new program requirements"
    inconsistent with Milestone B (S9). DoDI expects boards to approve only changes that are
    "critical" and funded (S10). A DESCOPE channel exists alongside the add channel (S9 (c)(2)(B)).
M5. TRIAGE A LATE FINDING BY BLAST RADIUS AND SEVERITY. Only the top class blocks.
    - Class I vs Class II ECP: only changes to the functional or allocated baseline, cost or
      milestones go to the customer board (S8).
    - A deviation or waiver releases a requirement without changing the baseline (S3, S8).
    - AMC 20-189: only unmitigated "Significant" OPRs must close before approval. Every other
      OPR ships open, with a recorded justification (S17).
M6. TRACEABILITY LOCALIZES THE REOPENING. A new hazard or requirement reopens only its trace
    subtree (STPA p39, S14; NASA bidirectional traceability, S7). It never reopens the whole
    baseline.
M7. THE COST EVIDENCE FOR HOLDING THE LINE. GAO (March 2008, quoted in S9): programs with
    requirement changes after development began saw cost growth of 72 percent, against 11
    percent for programs without changes. This is the empirical case for a presumption against
    change, and it is why DoD wrote CSBs into statute.

Mapping to the operator's complaint (inferred). The loop "are we 100.00% complete? -> actually
one more thing" is what you get when there is no frame (M1), no finite grid (M2), no TBD ledger
(M3), no baseline or board (M4) and no severity triage (M5). Every late finding is then treated
as a reason to reopen. In high-assurance practice a late finding is:
  (a) out of frame: a frame-change request to a board, with a presumption against it;
  (b) in frame but an empty grid cell: a defect, fixed locally along its trace;
  (c) in frame and already a named TBD: already planned, no action.
Only case (b) at top severity blocks progress.

## Sources

| id | source | how accessed |
|---|---|---|
| S1 | NPR 7123.1 App G (search result listing G-4 SRR, G-6 PDR, G-7 CDR tables) https://explorers.larc.nasa.gov/2023APPROBE/pdf_files/NASA02.%20NPR%207123.1C%20NASA%20Systems%20Engineering%20Processes%20and%20Requirements.pdf | WebSearch 2026-09-30 |
| S2 | NPR 7123.1D Appendix G, NODIS https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7123_001D_&page_name=AppendixG | WebFetch 2026-09-30 |
| S3 | NASA SE Handbook 6.5 Configuration Management https://www.nasa.gov/seh/6-5-configuration-management | WebFetch 2026-09-30 |
| S4 | IEEE 29148 "complete" (secondary: https://www.modernrequirements.com/?p=32595 ; preview https://webstore.ansi.org/preview-pages/ISO/preview_ISO+IEC+IEEE+29148-2011.pdf) | WebSearch 2026-09-30 |
| S5 | DO-178C Table A-3 (secondary summaries: https://afuzion.com/traceability/ , https://arxiv.org/pdf/2509.16844) | WebSearch 2026-09-30 |
| S7 | NASA SE Handbook 6.2 Requirements Management https://www.nasa.gov/seh/6-2-requirements-management | WebFetch 2026-09-30 |
| S8 | MIL-HDBK-61A ECP class / deviation (secondary: https://acqnotes.com/acqnote/careerfields/engineering-change-proposal-ecp , https://en.wikipedia.org/wiki/Request_for_waiver) | WebSearch 2026-09-30 |
| S9 | Sec. 814 FY2009 NDAA statute text + GAO quote https://wifcon.com/dodauth9/dod09_814.htm | WebFetch + curl 2026-09-30 |
| S10 | DoDI 5000.02 CSB summary (https://aaf.dau.edu/aaf/mca/develop-system/ ; https://www.gao.gov/assets/gao-14-466r.pdf) | WebSearch 2026-09-30 |
| S11 | IEEE 830 completeness definition (secondary: https://www.engr.mun.ca/~dpeters/7893/Notes/requirements.pdf ; https://rs.ieee.org/images/files/newsletters/2012/3_2012/The%20Elusive%20Definition%20of%20Requirements%20Completeness.pdf [418 on fetch]) | WebSearch 2026-09-30 |
| S12 | Luitel, Hassani, Sabetzadeh, arXiv:2308.03784v2 p.1, citing Zowghi & Gervasi IST 45(14) 2003 https://arxiv.org/pdf/2308.03784 | WebFetch saved PDF, text via pypdf 2026-09-30 |
| S13 | Jaffe/Leveson et al. 1991 completeness criteria (https://www.cs.washington.edu/homes/leveson/papers/completeness.pdf -> sunnyday.mit.edu, unreachable) | WebSearch 2026-09-30 |
| S14 | Leveson and Thomas, STPA Handbook, March 2018 https://www.flighttestsafety.org/images/STPA_Handbook.pdf (pp.16,19,20,31,36,39) | WebFetch saved PDF, text via pypdf 2026-09-30 |
| S15 | ISO/IEC/IEEE 29148 set-level "complete" (secondary: https://www.modernrequirements.com/?p=32595 ; https://www.archives.gov/files/contracts/hipgfi/ir-templates/ir-quality-standards-strs-pdd.docx) | WebSearch 2026-09-30 |
| S16 | DO-178C Section 7 SCM / PR-based change (secondary: https://github.com/PacoReinaCampo/PU-RTOS/wiki/chapter7 ; https://patmos-eng.com/?p=621) | WebSearch 2026-09-30 |
| S17 | EASA AMC 20-189 Management of Open Problem Reports https://www.easa.europa.eu/en/document-library/easy-access-rules/online-publications/easy-access-rules-acceptable-means-1?page=28 (FAA AC 20-189 PDF returned 403) | WebFetch 2026-09-30 |
| S18 | ISO 26262-3 item definition (secondary: https://presencis.com/regulations/iso-26262/article-3-item-definition/ ; preview https://webstore.ansi.org/preview-pages/ISO/preview_ISO+26262-3-2018.pdf) | WebSearch 2026-09-30 |
| S6 | STPA four UCA types (ICAO SRM STPA deck https://www.icao.int/sites/default/files/SMI/TrainingDocs/Chapter%202%20Safety%20Management%20Fundamentals/2.6-05-SRM-Methodology-STPA.pdf) | WebSearch 2026-09-30 |
