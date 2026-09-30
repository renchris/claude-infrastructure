# Root-cause taxonomy of the "one more hole" loop

Inputs: the eight per-shard forensic reports (`/tmp/rescomp/forensics/shard-0.md` … `shard-7.md`, 88 re-ask cases from `/tmp/rescomp/loop_asks.json`) and the four internal audits (`/tmp/rescomp/internal/close-assertion.md`, `stop-rule-machinery.md`, `plan-lifecycle.md`, `greenfield-cases.md`).
Canonical ledger: `/tmp/rescomp/taxonomy_holes.py`, 200 holes, one row each, carrying the shard's own label, materiality, findability, the merged class and a transcript or file receipt. The inline raw JSON in the task was cut off at shard 7 H15; rows 194–200 come from `shard-7.md` lines 149–155.
Counts: `python3 /tmp/rescomp/taxonomy_stats.py`. Each hole has one primary class. Rule for picking it: *the defect that let the hole survive to the completeness claim*.

## Answer first

1. **The loop is not research running out of road. It is checks that ran after the claim instead of before it.** Of 200 holes that surfaced after a "complete / good to close / 100%" claim:
   - **129 (64.5%) were findable by desk research.**
   - **70 of the 95 decision-changing holes (74%) were desk-findable.**
   - Only **6 (3.0%) were genuinely new operator requirements.**
2. **60% were misses inside the frame the research already had.** They came from six process defects: unverified premises (C3), populations never enumerated (C4), certifying instruments that could not fail (C5), research that existed but never reached the artifact (C6), holes the session's own edits created (C7), and adversarial review scheduled after the claim (C8).
3. **Another 11.5% (C1) were not discoveries at all.** The item was already known and on disk. The close was computed over a narrower frame: the session's diff, the wave's DoD, the git ledger, or a slice the agent picked. The operator's "100.00/100.00?" asked about the goal, so the same known residual was re-rendered as a "new" hole.
4. **Contact-only holes (C9, 15%) are real but mostly cheap.** **24 of 30 could have been probed on this machine during research**: run under launchd, run the handed command, query the live process, install and run the recommended tool, zero-quota probe. Only 6 needed production, an external tenant or elapsed time. Reality moving (C10) accounts for 4%.
5. **Re-asking manufactures a minority of holes directly.** 10 (5%) were created by the previous round's own rewrite, integration or fix. The 23 C1 holes are known items the question's frame shift relabels as new. The rest existed before the ask; the ask was simply the first adversarial audit ("Asking made me re-read my own work instead of recalling it", `~/.claude-next/projects/-Users-chrisren-Development-reso-web-app/5245ce63-….jsonl` @2026-08-27T20:26:24Z).
   - Bounded re-reads of a fixed artifact converge in 3–4 passes: 10→7→2 (`ba08cab8` 19:28:54Z) and 7→1→0 (`04235d35` 22:32:30Z).
   - Open-ended "find gaps" critic loops that fix in the loop do not converge: 23/21/24/28 new blockers and majors, none repeated (`7c395da7` 15:58:52Z), and 37→26→22→17→14→22→17→11→14→…→16 over 13+ rounds (`dcbd2f8e` 09:22:43Z, 18:24:30Z).

## The taxonomy (11 classes, MECE by primary cause)

Materiality: DC = decision-changing, REF = refinement, COS = cosmetic, NEW = new scope added by the operator, UNC = unclear. Findable earlier: Desk = desk research, Build/probe = only by building or probing, Op = only after the operator said it, None = not findable earlier.

| # | Class | Definition (assignment test) | n | % | DC | REF | COS | NEW | Desk | Build/probe | Op | None |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| C1 | **Claim frame narrower than the question** | The item was already known or recorded (a filed follow-on, a named loose end, a known loss, plan prose, a report ledger, an open decision). The claim was computed against a narrower frame: the diff, the wave DoD, the ledger, "not mine", or an agent-chosen slice. | 23 | 11.5 | 13 | 8 | 0 | 2 | 23 | 0 | 0 | 0 |
| C2 | **Operator intent or context arrived after the claim** | The hole needed information only the operator held. C2n (6): a genuinely new requirement. C2u (6): the intent, fact or prior decision existed but was never elicited at intake. | 12 | 6.0 | 2 | 0 | 0 | 10 | 2 | 0 | 10 | 0 |
| C3 | **Load-bearing premise asserted without a primary check** | A stated fact, figure, blocker or cost was false when written. It came from a doc list, code comment, docblock, vendor README, blog, memory, inherited plan row, stale index or repo record instead of the code, the live store or a measurement. | 29 | 14.5 | 12 | 14 | 3 | 0 | 26 | 3 | 0 | 0 |
| C4 | **Population never enumerated** | A member of the relevant space was never considered. Examples: an option (including "use what exists"), a candidate, caller, instance, platform, execution context, account or tenant, concurrent actor, publication surface, hazard, prior invariant, evidence source, decision, or the fleet case. | 32 | 16.0 | 22 | 10 | 0 | 0 | 29 | 3 | 0 | 0 |
| C5 | **Certifying instrument could not discriminate** | The check that backed "done" ran but could not fail on the defect. Examples: a blind predicate, a presence-only or provenance-only check, a vacuous self-comparison, a misread field, a harness that does not match production, n=1, a broken tool read as a negative, a grep-able DoD, or recall in place of re-execution. | 29 | 14.5 | 8 | 20 | 1 | 0 | 13 | 15 | 1 | 0 |
| C6 | **Existing research failed to reach the artifact** | The finding existed (on disk, in a prior session, in a sibling plan, in /tmp, in the research doc) and was dropped in synthesis, lost across a recycle, never persisted, never re-read, or duplicated by a second lead. | 12 | 6.0 | 7 | 5 | 0 | 0 | 12 | 0 | 0 | 0 |
| C7 | **Hole created by the session's own edits** | The artifact became wrong because of the previous round's edits: an append that was never integrated, a rewrite, script assembly, a local-span review fix, a later global change, or critic fixes that added new surface. | 10 | 5.0 | 3 | 6 | 1 | 0 | 8 | 2 | 0 | 0 |
| C8 | **Adversarial review sequenced late or not saturated** | The review that finds the defect existed but ran after publish or land, stopped at one pass, accepted dead or partial units as clean, or let the build fire with research still open. | 8 | 4.0 | 5 | 3 | 0 | 0 | 8 | 0 | 0 | 0 |
| C9 | **Contact-only** | The property lives in the real target: the deployment interpreter, target OS, a live process, real artifacts, production scale, a real tenant, or time. It was certified on a stand-in (a stub, fixture, dev shell, simulator, a quiet box, n=1) or not run at all. | 30 | 15.0 | 13 | 15 | 1 | 0 | 1 | 29 | 0 | 0 |
| C10 | **Reality moved** | The world changed during or after the research: sibling commits, an operator deploy, external drift, credential expiry, an upstream release, or the research perturbing its own subject. | 8 | 4.0 | 4 | 3 | 1 | 0 | 3 | 1 | 0 | 4 |
| C11 | **Acceptance criterion never operationalized** | "Done" had no falsifiable test. Examples: a superlative ("maximally", "100th percentile") with no measured ceiling, taste judged by structural proxies, a ban-list used as acceptance, no positive reference, no pre-registered thresholds, a perfection hold with no expiry. | 7 | 3.5 | 6 | 1 | 0 | 0 | 4 | 1 | 2 | 0 |
| | **Total** | | **200** | 100 | **95** | **85** | **7** | **12** | **129** | **54** | **13** | **4** |

The one UNC hole (id 134, the tenant-only probes) sits in C9.

Hole ids per class, for lookup in `taxonomy_holes.py`:
- C1: 1, 3, 8, 13, 21, 23, 25, 39, 40, 58, 60, 63, 79, 99, 101, 113, 128, 143, 158, 160, 163, 169, 192
- C2: 36, 80, 84, 107, 125, 168, 177, 185, 186, 194, 198, 200
- C3: 4, 9, 17, 18, 19, 27, 29, 30, 31, 38, 52, 105, 106, 109, 118, 130, 136, 138, 140, 145, 151, 152, 154, 162, 166, 167, 171, 183, 184
- C4: 10, 15, 33, 42, 44, 51, 54, 57, 68, 69, 70, 87, 88, 90, 100, 110, 111, 120, 126, 141, 147, 155, 159, 173, 175, 181, 182, 187, 190, 193, 196, 197
- C5: 2, 7, 12, 14, 20, 22, 24, 32, 37, 43, 45, 48, 59, 64, 67, 71, 72, 73, 78, 81, 83, 89, 93, 97, 114, 117, 122, 127, 129
- C6: 55, 61, 76, 77, 104, 108, 123, 135, 139, 172, 176, 178
- C7: 6, 85, 86, 115, 132, 149, 161, 180, 188, 195
- C8: 35, 47, 74, 75, 137, 150, 174, 189
- C9: 16, 26, 28, 34, 41, 50, 53, 82, 91, 92, 94, 95, 98, 102, 112, 116, 121, 124, 131, 133, 134, 142, 144, 146, 153, 156, 157, 170, 191, 199
- C10: 5, 46, 49, 96, 103, 119, 164, 165
- C11: 11, 56, 62, 65, 66, 148, 179

## Per class: mechanism, the step that prevents it, and receipts

### C1: Claim frame narrower than the question (23; 13 DC; all desk-findable)

**Mechanism.** The close is computed by `wrap-ledger.sh` / `/are-we-done` over git and session facts. `are-we-done.md:70-72` defines "exhaustively" as a git property, and REMAINDER counts `- [ ]` boxes: only 4 of 76 DoD files carry any box (`close-assertion.md` §1.3). An absent DoD still reads ✅ (`wrap-ledger.sh:2286-2288`). So "Good to close: yes" is true of the diff and silent on the goal. The next "100.00?" re-judges on the goal frame and re-renders items that were already known.

**Prevention step.** Keep two separate verdicts:
- a session-ledger verdict;
- a goal verdict, computed against a frozen, enumerated acceptance matrix for the whole program.

The follow-on line must be *computed*, by reconciling every item in every store to one of three dispositions: done, not-required-with-reason, or filed. The stores are plan prose, research-doc residuals, report ledgers, backlog rows, open decisions and dirty files. It is never written by hand.

**Receipts.**
- *Floor plan:* "Good to close: yes — complete … no loose ends" (`855b332e` L1135), then "No — and not close. Roughly a quarter of the way there" (L1185).
- *limit-detect:* "✅ Complete & live on trunk — safe to close" (`7f533f05` 09:06:30Z), then "0 of 7 waves are built. 'Safe to close' described *my session's* state, not the job" (09:08:24Z).
- *git-forest:* "follow-on: none filed" (`cb227486` 18:16:28Z), then 8 known items including "Two ideas sit above your own 90% implement-threshold" (18:28:30Z).
- *sevenrooms:* "exhaustively done" (`ac0f0123` 19:48:24Z), then "about 93 of 100", where every gap was already dated (20:20:22Z).
- *In writing, in the plan itself:* reso `FLOOR_PLAN.md:63-66`, "each time true of the wave then running and false of the question asked".

### C2: Operator intent or context arrived after the claim (12; C2n 6 new, C2u 6 unelicited)

**Mechanism.** The genuinely new asks (C2n: 80, 84, 125, 168, 177, 200) are legitimate scope growth. The C2u cases (36, 107, 185, 186, 194, 198) held intent or facts that already existed but were never asked for. Examples: the apex-domain decision (`c0f857b6` op 2026-09-20T17:47:22Z); the in-person agreement with the author (TM2 `dcbd2f8e` 20:31:36Z); the operator's release-program deliverable (`7c395da7` 23:07:02Z); the one-command preference already in CLAUDE.md (198). None of the 12 is a research miss. All but two (107, 194) were logged as new scope.

**Prevention step.** Run an intake interview before wave 1 covering: the deliverable's consumer, operator-private facts and relationships, prior operator decisions mined from transcripts and `msg`, and what "not lacking" means. The operator co-signs the acceptance matrix. Later additions are logged as `Scope (grown, cause=operator)` and not scored as take-backs. Today `Scope (grown)` has no cause field and no reader (`close-assertion.md` G5).

### C3: Unverified load-bearing premise (29; 12 DC; 26 desk)

**Mechanism.** A decision rests on a secondhand claim that one read of the primary source would refute. This is also the largest class in the plan-lifecycle audit ("false when written": 43 of 158 moves, 27.2%, `plan-lifecycle.md` §3).

**Prevention step.** Keep a premise register. Every load-bearing premise carries its source tier (code, live store, measurement, or secondary) and a date. Any secondary-tier premise under a decision is measured or flagged before the decision is posed. Inherited figures are re-derived. A store's own staleness warning is honored.

**Receipts.**
- "I quoted a list that had been rescoped away" (`d0630e1c` 21:28:56Z).
- "I asked you for data the mechanism already computes. Sixth stale-premise instance in this file" (`d41563e3` L1005).
- "My message search used an index last built on 09-24, and the tool even warned it was stale" (`7c395da7` 01:21:32Z).
- "1 of 1 derivation sites; 5 restatement sites … vs 0 measurements" (`d90959db` 00:36:21Z).
- SMIL "never measured … no research document behind the SMIL decision" (`7a375ee2` 01:58:30Z).

### C4: Population never enumerated (32; 22 DC, the most decision-changing class; 29 desk)

**Mechanism.** Research answered the question inside the space it happened to look at. Missing members:
- the option "use what already exists": the Amplify CDN already honored `s-maxage`, "the whole A/B decision was moot" (`c0f857b6` 21:41:03Z, 22:47:47Z);
- a candidate already in the fork, Parakeet Unified (`989f6dbf` 2026-09-28T05:21:27Z);
- the second checkout (`089dda26` 03:51:45Z);
- an invisible caller, `gen/config.py:76` (`089dda26` 03:22:19Z);
- the fleet case (`LIMIT_RECOVER_100P.md:933-942`);
- the public mirror (`7c395da7` 09:58:27Z);
- the access logs (`c0f857b6` 23:46:07Z);
- the operator's own M365 tenant (`0612873d` 05:20:00Z);
- the upstream base version, which a freeze clause settled silently (`989f6dbf` line 813 vs 05:56:57Z).

The critics audit what the plan *says*, not its unstated premises (`shard-7.md` pattern 1).

**Prevention step.** Before any recommendation, produce census artifacts, each checked for coverage:
- options, including "do nothing" and "use what exists";
- candidates enumerated from the repo;
- callers and instances;
- platforms and execution contexts;
- accounts and tenants;
- concurrent actors;
- publication surfaces;
- prior invariants;
- evidence sources, including logs and issue trackers;
- unstated baseline decisions.

A premise critic reads the census, not the prose.

### C5: Certifying instrument could not discriminate (29; 8 DC; 13 desk / 15 build)

**Mechanism.** Every "done" rested on a check that was never shown red on the gap it claims to rule out:
- "Preflight … PASS 46/0/0 while unattended recovery is structurally impossible" (`6ee03e6e` L1576);
- "the proof above is a grep over the file", followed by "the local fallback … can essentially never fire" (`ba08cab8` 16:41:11Z → 19:04:07Z);
- "every quotation and figure traces … factually it is sound", followed by "four statements its own source refutes" (`04235d35` 17:12:09Z → 17:54:16Z);
- "every one of them invoked the tool *correctly*" (60 selftests and 47 mutants passed a tool that spins forever; `d90959db` 20:24:34Z);
- the plan-lifecycle positive control: 45 of 58 acceptance commands were unsound when run against trunk before build (`plan-lifecycle.md` §4.5).

**Prevention step.** A predicate may certify "done" only after it has gone red on a planted defect (a discriminating control). Re-execute rather than recall. Match the harness to the production payload. Use n>1 with a load control. Check the source for contradictions, not just for provenance.

### C6: Existing research failed to reach the artifact (12; 7 DC; all desk)

**Mechanism.**
- "I only read its headline … left it out of the synthesis document entirely" (744-line axis, `22100d17` 04:44:30Z).
- "I truncated that section when reading it" (`ba08cab8` 20:10:19Z).
- "Zero hits for 'houndstooth' … nothing from Sept 13 was ever written down" (`d71e8e48` 04:02:37Z). This reversed an "already 100th percentile" close.
- The 08-26 keep-warm ranking was "never re-read" (`c0f857b6` 17:51:29Z).
- A second lead declared a live sibling dead and wrote a parallel plan (`7f533f05` 20:55:21Z vs `11569d45` 21:35:35Z). Three plans for one topic followed: LIMIT_RECOVER_100P, LIMIT_DETECT_100P, FLEET_V2.

Machinery gap: `docs/research/` has 404 entries and no index or coverage register (`stop-rule-machinery.md` §4).

**Prevention step.**
- Search a research index, including transcripts, sibling plans and adjacent docs, at research start.
- Check mechanically that every research finding maps to a plan item or a recorded rejection.
- Persist evidence in the repo, never in /tmp.
- Allow one owner per topic, confirmed by a positive liveness signal.

### C7: Hole created by the session's own edits (10; 3 DC; 8 desk)

**Mechanism.**
- "None of these existed before the integration step … **The integration is the generator**" (`docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md:14`).
- "my own rewrite is where two of today's defects came from" (`04235d35` 17:57:10Z).
- "plan v2 was assembled by script … nobody has re-read the finished document": 20 defects (`989f6dbf` 05:26:16Z).
- CAP 5000 against "CAP stays 500": amendments were appended as §11 and never integrated into §3, and the implementer followed the stale row (`101dc59a` 09:22:23Z).
- "Each fix adds more machinery of its own … and the next round critiques that" (`7c395da7` 15:58:52Z).

**Prevention step.** Integrate changes instead of appending them. After the last edit, run a whole-artifact consistency read. After every rewrite, re-verify the changed spans and the spans that depend on them. Freeze the artifact before the final verification. When a critic finds a gap in added machinery, prefer deleting the machinery to patching it (`dcbd2f8e` 04:24:17Z: "delete, rather than patch, the process machinery").

### C8: Adversarial review sequenced late or not saturated (8; 5 DC; all desk)

**Mechanism.**
- "landing v1 now loses nothing", after which the verifiers refuted K3 and K4 (`2d71c6d8` 13:31:30Z; `screenshot-pipeline-2026-09-10.md:534-535`).
- The red team ran after synthesis ("All 138 assertions would still have passed", `d0630e1c` 20:14:13Z).
- r6 "died on the weekly quota limit and was written off as not decision-relevant" (`7a375ee2` 02:01:09Z).
- "The first run treated three dead critics as 'no gaps'" (`7c395da7` 04:20:53Z).
- W1 fired while r4/r7 were open (`3c73a9d9` rec 1152).
- One reading pass was treated as saturated: 10→7→2 (`ba08cab8` 19:28:54Z).

Machinery gap: OASIS is prose only; no code computes its α or ε (`stop-rule-machinery.md` S1). The one dry-round stop rule is advisory and scoped to Fable sweeps (S9).

**Prevention step.**
- Adversarial verification runs before any claim or land.
- Independent passes continue until new-finding yield falls below a declared threshold, and the curve is reported.
- A dead or partial slot blocks synthesis.
- A build cannot fire while "Open items" exist.

### C9: Contact-only (30; 13 DC; 29 build/probe). 24 were probe-able on this machine during research

**Mechanism.** The claim was certified against a stand-in. Examples: "the launchd job has been crashing on every single trigger since you installed it … `/bin/bash` … 3.2.57" (`4bc1159f` 18:31:29Z); "`it2 session text` … does not exist on this backend … the selftest stubs it" (`d90959db` 04:01:51Z); "status: complete rested on n=1" (`LIMIT_RECOVER_100P.md:319-321`); "pandoc is not installed" (`2825e1e5` 19:54:21Z).

Only 6 of the 30 needed a target this machine could not provide:
- 16: production sidecar;
- 34: deploy plus analytics;
- 95: Linux Amplify;
- 121: production deploy;
- 134: corporate tenant;
- 170: a scheduled weekly event.

The other 24 were cheap local contact deferred past the claim. Examples: the zero-quota `settings.local.json` probe (`2c6c3a09` 17:16:26Z); "drivable probes deferred" (`2825e1e5` 07:15:37Z); running handed commands.

**Prevention step.** Put a contact wave inside research, before sign-off. It covers spikes on the target interpreter and OS, live-process checks, real artifacts, production-scale n, and every handed command run by the agent. The positive control is reso `LIMIT_RECOVER_FLEET_V2`: W0 measure-first, then W0–W6 in about 1.5 days (`plan-lifecycle.md` §0.5). The irreducible residual (production, tenant, time) is declared at sign-off as budgeted post-build verification with a dated owner. It is not treated as a reopen.

### C10: Reality moved (8; 4 DC; 4 not findable, 3 findable by re-reading trunk or the registry)

**Mechanism.**
- "`93c60a8` landed Option B four hours ago" while Option A was being recommended (`c0f857b6` 22:30:05Z).
- Sibling `84a9e0e1a` changed the code 5.7 h before the Stage A recommendation (`869edb07`).
- Same-day `226b73888` "moves the tree under me" (`11569d45` 21:35:35Z).
- An expired Fly token caveat (`d02d8feb` 17:44:35Z).
- A research probe killed the subject (`2d71c6d8` 20:15:31Z).
- Plan-lifecycle puts environment change at 15.2% of plan moves; that corpus includes the operational drain.

**Prevention step.**
- Date-stamp every external fact with a re-check command.
- Record the trunk sha each conclusion was validated against.
- Re-read trunk and sibling activity before recommending and at the implementation gate.
- Check credential validity.
- Forbid research probes that mutate the live subject.

### C11: Acceptance criterion never operationalized (7; 6 DC)

**Mechanism.**
- "maximally fast" was never measured against the engine's 0.14 s ceiling (`39e7380e` L1191).
- "avoid AI slop' is not an instruction a model can follow" (`22100d17` 04:49:34Z).
- A ban-list was used as acceptance, with the palette "chosen by avoidance" (`4be23526` 18:59:07Z).
- "What 'perfect' should mean, as tests that can pass or fail" was raised only after "complete" (`0612873d` 05:20:00Z).
- A standing "reply once 100th percentile complete" hold left a warm lead unanswered for 21 days (`7193ec2b` 16:58:32Z).

The repo already names this root cause in exactly one place: `/ground-up` bans superlatives because they "make completion unfalsifiable — the exemplar's Stop-hook thrashed on exactly this" (`skills/ground-up/SKILL.md:14-18`). Neither `/research` nor the research-subagents skill carries that ban (`stop-rule-machinery.md` S11). The reso floor-plan plan had banned it too, and was answered with a superlative anyway (`855b332e` L1185).

**Prevention step.**
- Translate every superlative into measurable predicates, measuring the ceiling first.
- For taste, use a positive reference set, with the operator's eye as a named gate.
- Pre-register pass/fail thresholds and the branch taken on a negative result.
- Give perfection holds an expiry.

## Mapping of the shards' ad-hoc labels (every label → one class)

- **C1:** known-item-excluded-from-done ×3, verdict-scoped-to-diff-not-goal ×2, ledger-scope-vs-job-scope ×2, open-items-buried-in-plan-prose, attribution-dismissal-without-content-check, scope-narrowing, frame-silently-narrowed, house-rule-not-applied-as-acceptance, done-claim-not-diffed-against-ask, named-input-silently-dropped, success-proxy-substituted-for-goal, stale-measurement-and-undriven-known-item, completeness-frame-narrowed, scope-relative-completeness, dod-vs-optimum-frame, inventory-by-memory, close-scoped-to-narrow-dod (deps), rubric-switch-rerender, open-decision-parked-under-complete.
- **C2:** operator-new-requirement ×3, frame-narrower-than-operator-intent ×2, frame-exceeds-need, operator-requirement-not-mined, close-scoped-to-narrow-dod (laptop independence), operator-scope-growth, H15 (operator-private context), H19 (deliverable consumer), H21 (feedback requirement).
- **C3:** stale-secondary-source ×2, shallow-evidence-tier ×2, unmeasured-deferral-cost, unverified-blocker-premise, operator-frame-vs-architecture, unverified-premise, untraced-question-hides-live-defect, unverified-codebase-assumption, unprobed-premise, assertion-without-measurement, inherited-unmeasured-premise, stale-claim-not-rechecked, option-space-frozen-early (wildcard blocker), unverified-estimate, inherited-claim-unverified, unrederived-inherited-figures, vendor-claim-trusted, premise-from-docblock-not-measured, consumer-uses-wrong-lane, reachability-misclassification, lost-rationale-unmeasured-premise, premise-asserted, live-state-premise-unverified, memory-not-ledger, ungrounded-research-claims, stale-instrument-read-as-truth, claim-not-checked-against-source.
- **C4:** partial-enumeration ×2, hazard-found-only-by-adversarial-read, premature-ceiling-claim, unchecked-platform-matrix, in-frame-symptom-fixing, decomposition-gap, search-bounded-by-own-stores, incomplete-enumeration, candidate-space-truncated-question-substituted, unquestioned-architecture-premise, omission-blind-review, wrong-subject-instance, diagnosis-frame-excludes-remediation-surface, incomplete-enumeration-search-frame, option-space-frozen-early (existing CDN), available-data-not-consulted, wrong-question-frame, concurrency-never-in-frame, frame-shift-invalidates-invariants, environment-inventory-gap, execution-context-gap, unpinned-invariant-regression, candidate-frame-not-enumerated, environment-outside-frame, unexamined-baseline-premise, source-outside-search-frame, publication-surface-unmodeled, decision-on-partial-facts, single-instance-frame-misses-fleet-case, H17 (research question framed narrow), H18 (no fixed fact list).
- **C5:** instrument-misread ×2, harness-invocation-mismatch ×2, checked-by-claim-not-execution ×2, unexecuted-acceptance-criteria, tally-measures-classification-not-dod, measurement-validity-unchecked, instrument-blind-to-zero-signal, visual-defect-invisible-to-gates, green-gate-blind-to-property, claimed-not-executed (deploy ≠ execute), claim-by-recall, claim-without-observation, verification-misses-claimed-path, one-shot-probe-called-proof, vacuous-comparison, dod-as-format-check-misses-system-property, dod-omits-verification, false-negative-instrument, instrument-fidelity, provenance-not-contradiction-check, unit-proof-as-system-proof, racy-oracle, handed-command-unexecuted, weak-verification-and-dropped-known-item, premature-verdict-small-n, broken-instrument-false-negative.
- **C6:** research-to-plan-transcription-loss ×2, prior-research-lost, synthesis-drops-research-on-disk, evidence-not-persisted, synthesis-truncation, duplicate-parallel-research-stale-liveness, prior-research-not-reread, prior-research-lost-across-sessions, adjacent-research-not-consulted, no-prior-art-sweep-plus-false-resident-rule, ephemeral-evidence.
- **C7:** rewrite-reintroduces-defects ×2, appended-findings-leave-stale-rows, plan-amendment-not-integrated, integration-generated-contradictions, stale-summary, self-invalidated-artifact, unverified-integrated-artifact, critic-loop-generates-own-surface, H16 (critic loop with no stop rule).
- **C8:** publish-before-verify ×2, single-pass-not-saturated ×2, implementation-before-research-closed, partial-wave-accepted, design-unreviewed-until-pushed, absent-verdict-read-as-clean.
- **C9:** probe-only-unknown ×5, runtime-only-evidence ×2, build-time-discovery ×2, found-only-while-implementing ×2, claimed-not-executed ×2 (pandoc, SIGPIPE), test-env-not-deployment-env, close-on-one-shot-not-steady-state, repo-invariant-unknown, prod-env-parity-gap, landed-not-live-process-state, found-only-by-executing-in-real-env, environment-only-verification, build-time-defects, stubbed-path-never-executed, drivable-probes-deferred, environment-gated-unknowns, multi-step-state-sequence-untested, probe-only-reality, environment-mismatch, verification-needs-operation, validated-in-unrepresentative-conditions, H20 (claim read, not executed).
- **C10:** reality-moved-plan-stale, environment-drift, research-perturbs-subject, environment-changed-credential-expiry, reality-moved-concurrent-commits, concurrent-reality-change, stale-external-snapshot, stale-baseline-sibling-change.
- **C11:** superlative-never-operationalized, perfection-gate-blocks-delivery, unfalsifiable-criterion-verified-by-proxy, negative-gate-as-acceptance, missing-positive-reference, missing-dod-prerequisites, missing-methodology-checklist.

Judgment calls:
- 114: presence-only verification plus a dropped defect. Classed C5 (the weak check); C1 was the alternative.
- 131 and 191: stubs and n=1. Classed C9 (the truth lives in the real target), not C5.
- 69: candidate truncation plus question substitution. Classed C4.
- 36: frame larger than the need. Classed C2u, not C11.
- 153: every iOS figure came from the iOS 26.3 Simulator while the phone runs 18.7.8. Classed C9 (the truth lives on the real device and was certified on a stand-in), though the shard rated it desk-findable because reading the device version is a desk act. It is the one desk-findable C9 row; C4 (platform never enumerated) was the alternative.

Moving any one of these shifts a class by one hole and changes no conclusion below.

## The three questions asked

### 1. What fraction of re-ask holes were material at all?

| Materiality | n | % of 200 | % of the 188 excluding operator-added scope |
|---|---|---|---|
| decision-changing | 95 | 47.5 | 50.5 |
| refinement | 85 | 42.5 | 45.2 |
| cosmetic | 7 | 3.5 | 3.7 |
| new scope (operator) | 12 | 6.0 | — |
| unclear | 1 | 0.5 | 0.5 |

About half (47.5%) were decision-changing and 90% (180 of 200) were decision-changing or refinement; only 3.5% were cosmetic. The loop is not mostly noise. The decision-changing holes concentrate in C4 (22 of 32), C1 (13), C9 (13) and C3 (12). **70 of the 95 were desk-findable**: C4 20, C1 13, C3 11, C6 7, C5 6, C8 5, C7 3, C11 3, C10 2.

Caveat: materiality is the shard raters' single-pass judgment. At least one "biggest gap" was later dropped as moot once measured (id 178: `7640e8326`, stock passed 36/36). One "five standing reds" item was four-fifths already green (id 99, `26cd14be` 00:25:40Z). Read the decision-changing count as an upper bound.

### 2. Frame expansion vs miss inside the frame

| Bucket | Classes | n | % | DC |
|---|---|---|---|---|
| Frame expanded by the operator (new requirement) | C2n | 6 | 3.0 | 0 |
| Frame mis-specified at intake (intent existed but was never elicited, or the criterion was unfalsifiable) | C2u + C11 | 13 | 6.5 | 8 |
| Claim frame narrower than the question (known item re-rendered; nothing new learned) | C1 | 23 | 11.5 | 13 |
| **Miss inside the frame** | C3–C8 | **120** | **60.0** | 57 |
| Outside desk reach: contact-only or reality moved | C9 + C10 | 38 | 19.0 | 17 |

- Of the 38 outside desk reach, 24 were contact probes runnable on this machine during research, 3 needed only a re-read of trunk or the registry, and 1 (a login token whose hidden lifetime expired, id 96) needed only a credential-validity check. **Only 10 (5%) were unreachable before the claim by any upfront process on this machine**: 6 needed production, a tenant or elapsed time, and 4 were unforeseeable drift.
- Counting all frame change on both sides (C1 + C2), 35 holes (17.5%) were frame expansion. Only 6 of those are frame expansion in the operator's sense. The other 29 are the claim's frame being narrower than an operator frame that already existed.
- Triangulation with an independent unit, the plan edits in `plan-lifecycle.md` §3 (158 goalpost moves, single rater): new operator requirement 4.4% vs this ledger's 3.0%. "False when written" plus critic plus missed axis plus lost research sum to 54.5%; C3 + C4 + C6 + C7 + C8 here sum to 45.5%. Verification-by-building is 25.9% there vs C9 + the build-found C5 holes (22.5%) here. Environment change is 15.2% there vs C10 4% here; the plan corpus includes a 27-day operational drain.

### 3. Does re-asking itself manufacture holes?

**Partly. Directly it manufactures a small share; the larger shares come from relabeling and from checks that simply never ran before the claim.**

- **Directly manufactured by the previous round's own work, C7: 10 holes (5%).** These come from rewrites, integrations, script assembly, append-not-integrate edits, and critic fixes that add new surface. This is the only class where the act of responding to a re-ask creates the next hole. It becomes unbounded under open-ended critic loops: "about half are operational details, often introduced by the previous round's own fixes" (`dcbd2f8e` 09:22:43Z). There, the "uncatchable" bucket moved with its definition, 13 vs 5 (17:16:36Z).
- **Relabeled, not discovered, C1: 23 holes (11.5%).** Each rephrasing ("from here", "nothing can beat it", "what brings us to perfection") moves the reference frame. Known, dated residuals are then re-rendered as gaps: "Every item was already known and dated … no new fact was discovered" (`ac0f0123`, hole 169).
- **The machinery is built to produce holes on demand.**
  - Every gap instrument is required to return a positive count: the critic must "name 1-3 plausible axes the decomposition is MISSING" (`agents/research-decomposition-critic.md:37,80`); the negative-space trigger must "List 3" (`skills/research-subagents/SKILL.md:798,823`); the worker must "Find 2-3 gaps" (`agents/deep-research.md:187`).
  - The only exit is the user's own exclusion words (`SKILL.md:800-803`), and a "re-check" is told to apply the rule more aggressively (`SKILL.md:944-948`).
  - There is no definition of materiality anywhere (`close-assertion.md` §2). F1 passes any refinement under "nothing left on the table". Every Stop arm guards against a false "done" and none guards against an unbounded "not done" (G7).
  - Result: the only rule-compliant reply to "are we 100.00?" is "No, running X now" whenever any further check is imaginable.
- **What re-asking did not do: create the other ~83%.** Those holes existed before the ask. The ask was the first adversarial audit, because none ran before the claim:
  - "Let me not answer that from optimism" (`39e7380e` L1167);
  - "This deserves a real audit, not an assertion" (`d41563e3` L117);
  - "The check did not exist until the question was asked" (`close-assertion.md` §4, `989f6dbf` 05:26:16Z).
- **Convergence evidence decides the design.**
  - Bounded passes over a fixed artifact converge: 10→7→2 (`ba08cab8`); 7→1→0 fatal (`04235d35`); natural-TTS's pre-declared "round 2 of 2, the last" shipped in about 2 days (`greenfield-cases.md` row 5).
  - Unbounded, fix-in-loop, required-output critics do not: 23/21/24/28, and 37…16 over 13+ rounds.
  - The plans that closed and stayed closed ran their verification before build: DOCS_CONSOLIDATION_100P in 25.75 h, never reopened; FLEET_V2's pre-build skeptics found 7 fatal and 30 major defects (`plan-lifecycle.md` §0.5).

## What the taxonomy implies (evidence-tied, not a design)

- **About 89% of holes can be moved in front of the claim with steps that already have working exemplars in this corpus.** That is 178 of 200: everything except the 12 C2 holes (operator-held information, though the 6 C2u holes are the target of an intake interview) and the 10 C9/C10 holes that were unreachable or unforeseeable. The one step not yet exemplified is "census before recommendation" (C4). It is the most decision-changing class, and it is the step the critics are structurally blind to.
- **The per-class prevention steps, in pipeline order:**
  1. At intake: an interview plus a falsifiable acceptance matrix (C2u, C11).
  2. A premise register (C3) and census artifacts (C4) before any recommendation.
  3. A contact wave inside research (C9).
  4. Discriminating controls on every certifying check (C5).
  5. Traceability from findings to plan items, plus persistence (C6).
  6. Integrate-then-reread-whole (C7).
  7. Adversarial passes before the claim, with a yield-curve stop and dead-slot blocking (C8).
  8. Date-stamped facts and a trunk sha, re-checked at the build gate (C10).
  9. A computed two-level close (C1).
- **A re-ask after that can be typed and scored rather than reopened.** Each finding is classed as an in-frame miss (C3–C8, reopens the verdict if material), a frame expansion (C2n, logged as scope growth), a relabel (C1, answered from the ledger), a contact residual (C9, already budgeted), or drift (C10, re-validation). Today the system records all five identically as "No" (`close-assertion.md` §4).

## Verification (re-run after the 2026-09-30 15:26 CDT reboot)

This file came back with the rebuilt corpus (16:01), but the counting script it cites did not. This run re-derived everything instead of trusting the restored text:

- **Counts.** Recreated `/tmp/rescomp/taxonomy_stats.py`, which loads `taxonomy_holes.py` and recomputes every table cell above. `python3 /tmp/rescomp/taxonomy_stats.py` prints 200 holes with ids 1..200 contiguous. Class totals are 23/12/29/32/29/12/10/8/30/8/7, materiality totals are DC 95 · REF 85 · COS 7 · NEW 12 · UNC 1, findability is D 129 · P 54 · O 13 · N 4, DC-and-desk is 70, and C3–C8 is 120 (60.0%). All match the tables cell for cell.
- **Ledger against shards.** The per-shard row counts (26/31/37/22/26/20/17/21) match the task's raw JSON case by case, and `shard-2.md`'s own hole table (37 rows; DC 21 · REF 13 · COS 1 · NEW 2; desk 24 · probe/build 9 · operator 4). The ledger's COS (7), NEW (12) and UNC (1) rows are exactly the raw JSON's cosmetic, new-scope and unclear rows. The 7 shard-7 rows past the JSON truncation (194–200) match `shard-7.md:149-155`.
- **One inconsistency upstream, not in the ledger.** `shard-0.md:71` summarizes "17 decision-changing, 9 refinement; 17 desk, 7 build". Its own rows, and the task's raw JSON, give 16/10 and 16 desk / 8 build/probe. The ledger follows the rows.
- **One ledger wording fix.** Row 191 said "n=5 gave 1/5", while the raw JSON said "(1/4)". The primary source reads "5 sessions … 1 RECOVERED / 4 PARTIAL" (`docs/plans/LIMIT_RECOVER_100P.md:321-323`), so the row now says "1 recovered, 4 partial". Both earlier readings were halves of that sentence. No count changes.
- **Citations resolved on disk.**
  - `agents/research-decomposition-critic.md:37,80` ("name 1-3 … axes").
  - `skills/research-subagents/SKILL.md:798,823` ("List 3").
  - `agents/deep-research.md:187` ("Find 2-3 gaps").
  - `skills/ground-up/SKILL.md:14`.
  - `commands/are-we-done.md:70` ("exhaustively").
  - `scripts/wrap-ledger.sh:2286` (`DOD = absent` branch).
  - `docs/lessons/integrating-review-findings-by-local-edits-manufactures-contradictions.md:14` ("The integration is the generator").
  - `docs/plans/LIMIT_RECOVER_100P.md:7,319,384,933`.
  - `internal/plan-lifecycle.md:9,82` (158 moves: 4.4% new requirement, 27.2% false-when-written, 25.9% build-only, 15.2% drift) and `:13` (45 of 58, 25.75 h).
  - `internal/close-assertion.md:51,195,203,208` (4 of 76 DoD files; G5; G7).
  - `internal/stop-rule-machinery.md:21,29,31,57` (S1, S9, S11, 404 entries).
  - `internal/greenfield-cases.md:33` ("round 2 of 2, the last").

## Caveats

- **Raters.** Hole extraction, materiality and findability are single-pass judgments by eight shard agents. The merged class is a single pass by this unit. There is no second rater.
- **Denominator.** 200 holes from 88 asks. Cases 16, 70, 84, 86 and 87 were irrelevant. Seed asks 46 and 49 were folded into 48 and 51. Case 82 was noted but not scored.
- **Coverage.** The corpus is completeness re-asks only. Research that closed and was never re-asked is not in the denominator, so these rates describe the loop, not all research.
- **"Findable by desk" is hindsight-assisted.** For C4 in particular, it means the member was enumerable from sources on hand, not that a reasonable reader would have thought of it.
