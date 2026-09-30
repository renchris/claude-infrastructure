# Shard 7 — transcript forensics, cases 77–87

Source: `/tmp/rescomp/loop_asks.json` indices 77–87. Extraction scripts: `/tmp/rescomp/forensics/s7/extract.py` and `span.py`; raw per-case dumps are `/tmp/rescomp/forensics/s7/case<N>.txt`, with the longer after-spans in `c78succ.txt`, `c80after.txt` and `c83after2.txt`.

Transcript shorthands:
- **VI** = `~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/989f6dbf-0216-45d0-a061-f998c29ab27c.jsonl` (VoiceInk/Willow latency plan)
- **VI2** = `~/.claude-quaternary/projects/-Users-chrisren-Development-voiceink/46bc0436-c91c-45bd-83fc-c4c8f35abfd4.jsonl` (the successor handed off to at case 78)
- **TM1** = `~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/7c395da7-fbbe-4123-8bd5-2456787d12c3.jsonl` (TrueMemory lead)
- **TM2** = `~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/dcbd2f8e-b1c0-464f-b729-438da2222446.jsonl` (the TrueMemory lead after its recycle)
- **LR** = `~/.claude-next/projects/-Users-chrisren-Development-reso-management-app/83010792-5d10-4f88-b481-49300acc8fc5.jsonl` (limit-recover)
- **ACS** = `~/.claude-quaternary/projects/-Users-chrisren-Development-agent-context-sync/46d14e14-130a-4dfb-8a2a-e0e7c9ae4659.jsonl`

## Per-case table

| # | ts (UTC) | Project | Relevant? | Prior claim before the ask | What surfaced after the ask | Holes |
|---|---|---|---|---|---|---|
| 77 | 09-28 05:26 | VoiceInk latency plan | yes | 05:21:27 "Nothing left can be settled by more desk research… 90% that the plan runs start to finish without re-planning" | "No, not yet": the script-assembled plan had never been read end to end (20 defects). The operator then asked about upstream, which flipped the plan to rebase first | H1, H2 |
| 78 | 09-28 06:12 | VoiceInk | yes (methodology ask) | 06:11:56: five decisions left, rebase first at 90% | Upstream issue #956 explains the 15 silent recordings. The session then hands off; the successor (VI2) re-anchors, finds 17 bad anchors, and runs W1 without further regress | H3 |
| 79 | 09-28 23:07 | TrueMemory | yes | 22:43 / 23:04: "don't contribute upstream, 90%"; the author "never replied" | The operator redirects: a full release plan, not a yes/no on fixes. A dedicated research session is fired | H4, H5, H6 |
| 80 | 09-29 01:36 | TrueMemory | yes | 01:21 "adoption program finished; upstream plan written and on trunk"; 19 PRs in two batches, 82% | The operator widens scope to "TrueMemory 2.0". The 2.0 workflow runs 4 critic rounds without converging, a security exposure is found, and one decision flips | H7, H8, H9, H10, H11 |
| 81 | 09-29 03:36 | limit-recover (reso cwd) | yes | `LIMIT_RECOVER_100P.md:7` "Status: COMPLETE 2026-09-10"; §9 reopened 09-19; live incident 09-29 | Bare-checkout `set -e` death, an ownerless lock, auto-recover off; the fleet architecture is replaced by FLEET_V2 | H12, H13, H14 |
| 82 | 09-29 19:37 | agent-context-sync | partial (no prior claim in session) | none; first prompt of the session | The README says "There is no implementation yet." The operator had lost track of the repo's state | noted, not scored |
| 83 | 09-29 20:32 | TrueMemory 2.0 | yes | 20:27:50 "run the full 2.0 program, 85%", paced by the author's replies | The operator reveals an in-person agreement with Josh. The plan is reshaped, a replan critic loop runs 13+ rounds without converging, and a stop rule is ruled | H15, H16, H17, H18 |
| 84 | 09-30 03:05 | personal deadlines | no | none (a kickoff) | 108-item deadline inventory | none; pattern note only |
| 85 | 09-30 04:39 | agent-context-sync | yes | 02:51:54 and 04:32:07 "Good to close: yes. Nothing of mine is open" | 03:23: the operator wants a one-prompt setup. 04:39: the answer to "does it report friction?" is "No." | H19, H20, H21 |
| 86 | 09-30 04:48 | cc-backlog master plan | no | none (a kickoff) | a 12.6 h audit; the ledger moved during the run | none; pattern note only |
| 87 | 09-30 18:50 | this workflow's own trigger | no (meta) | — | — | — |

---

## Case 77 — VoiceInk latency plan, the ask at 05:26:09

**Prior claim** (VI 2026-09-28T05:21:27Z):
> "**Answer: yes, there was more to research. It's now done, and the plan has been rewritten as v2.** Nothing left can be settled by more desk research. Every remaining unknown needs your input or a live-app measurement… My conviction is 90% that the plan runs start to finish without re-planning."

This came after an earlier claim at 23:53:48Z on 09-27 ("the plan is complete, but it is not 100% certain… 85%") and an eight-track "voiceink-plan-endgame" workflow (23:58:36Z) that included "Three adversarial reviews of the plan: … whether anything is missing".

**Response** (05:26:16Z):
> "No, not yet. One check remains that doesn't need you: plan v2 was assembled by script from about 40 changes, and nobody has re-read the finished document end to end."

Then at 05:30:58Z:
> "The consistency review found 20 real but small defects: numbers that disagree between sections, a duplicated bullet, missing file owners and a mislabeled pin." (fixed in `dbc073f7`)

**Operator's next prompt** (05:27:05Z): "Should we bump up our pinned version of our voiceink to the latest voiceink public commit/release before we consider these overhaul changes?"

Answer at 05:56:57Z: "**yes, rebase onto v2.20 first.** It changes what the plan is built on…
- Upstream removed a text-normalizing step from all Parakeet output…
- Upstream already did some plan items. The Gemini 3.7 thinking bug is fixed. The install build now makes an optimized (Release) build, so our slower-Debug-build measurement stops mattering…
- every file path and about 80% of line references have moved."

Of 31 local commits, 10 needed hand-merging.

**Were the facts already on hand?** Yes. The first research report, relayed at VI line 134 (09-27T21:06:24Z), already said: "Merging 223 upstream commits will conflict: upstream reorganised its source tree in `16b61ac3`." Ten minutes before the ask, the endgame edit script (VI line 813, 05:16:32Z) *fenced off* the upgrade instead of asking about it: "**No `voiceink-update upgrade` until W4 closes.** … v2.20 is already being offered daily." So the base-version choice was settled silently, by default: "freeze and build on the stale base." It was never raised as a decision with a conviction number, and none of the three "what's missing" reviewers challenged it.

## Case 78 — "Should you self-recycle and re-equip with a goal…" (06:12:06)

This is a methodology ask, not a completeness question. The turn before it (06:11:19Z) ran a last check, "whether v2.20 has known problems", and reported (06:11:56Z):
> "**New finding, now in the plan's Phase R (`273efc56`):** your 15 silent recordings likely come from an upstream bug (#956). A mic sample-rate change, as happens with AirPods, leaves the recorder capturing nothing."

That search of upstream's issue tracker was prompted by the rebase question. It had never been in the research frame. After handing off (06:13:09Z), the successor VI2 re-anchored the plan: 52 lines changed and 17 anchors flagged by its verifiers (VI2 16:14:10Z). It completed Phase R and W1 and ran the tests ("38 passed, 0 failed", 16:45:23Z). It then blocked on operator inputs (paid Gemini tier, API keys, test-case approval). The operator's listening check grew from "74 clips, ~18 min" (05:21) to "85 rows, about 35 minutes" (VI2 17:12:40Z) because the rebase invalidated the first sheet. No further "one more thing" regress appears in VI2.

## Cases 79 and 80 — the TrueMemory upstream plan

**Prior claim** (TM1 22:43:14Z / 23:04:24Z): "Should we send our TrueMemory fixes to its author? My advice: no, not now… **90% sure.** The author has never accepted an outside contribution… your message got no reply."

**Operator at 79** (23:07:02Z): "don't just jump straight to TrueMemory fixes, we have to dedicated session fully research the 100.00/100.00… plan for TrueMemory, including our Agent Teams roadmap, and our publishing PR description and master PR/issue/release with 'stacked PRs'…"

**The dedicated session's result**, relayed at TM1 01:21:32Z:
> "**Recommendation: yes, in two batches. Conviction 82%.** … **The author did reply on 09-27 and invited PRs.** I said no reply existed; I was wrong. My message search used an index last built on 09-24, and the tool even warned it was stale. **There is nothing to sign.** Opening any PR accepts TrueMemory's Contributor Agreement."

**Operator at 80** (01:36:04Z): the recap called the program "finished". The operator's reply: "We need to exhaustively research upfront… master PR and release to bring EVERYTHING we can absolutely touch to 100th percentile… as TrueMemory 2.0."

**What the 2.0 workflow surfaced** (TM1, see `c80after.txt`):
- **A false clean pass from dead critics** (04:20:53Z): "if fewer than 2 critics come back in a round, it reports that instead of calling it a clean pass. The first run treated three dead critics as 'no gaps'."
- **A security exposure** (09:58:27Z): "`main` is copied to the public repo every 3 hours. The 19-PR plan landed yesterday contains the full text of an unfiled TrueMemory security advisory. It isn't public yet only because the copy is blocked by 27 email-style findings in the same files."
- **Non-convergence** (15:58:52Z): "The loop didn't converge: each round's critics found 23, 21, 24, then 28 new blockers and majors, none of them repeats. Each fix adds more machinery of its own (publish scripts, a state file, a watcher), and the next round critiques that. Every checker is green." It ended with 38 known gaps: 2 blockers, 26 majors, 10 minors (16:00:09Z). One re-check blocker was "Day-0 evidence that only a fork run can produce" (11:16:27Z).
- **A decision flip** (17:43:40Z): "How do we handle the security issue we've already published? … **The research changed the picture:** The issue appears in four public places, not two, and the main study doc's line 1053 is outside the folder." The recommendation moved from "remove the folder" to "redact".

## Case 81 — limit-recover "zero human, parallel" (03:36:30)

**Prior claim on disk**: `docs/plans/LIMIT_RECOVER_100P.md:7` "Status: COMPLETE 2026-09-10". Its §9 (`:319-321`) reads: "REOPENED 2026-09-19 — the n=5 production run refutes 'complete'. `status: complete` rested on n=1 (one throwaway, one-turn-old, self-spawned pane on a quiet box)… **1 RECOVERED / 4 PARTIAL**." The work was re-closed after W1–W7 (`b73aa3819`, 09-21).

**Live incident, 09-29** (LR 03:36:09Z):
1. "Recovery died on a line that only reads the repo folder for context (`lr-handoff.sh:581`, under `set -e`). It failed because the shared reso checkout had been flipped to 'bare' mode."
2. "The background poller retried at 03:07 and left a lock folder with no owner file, so `cc-lr` refused to take it over for 30 minutes."
3. "Automatic recovery already exists but is switched off… The plan left that as your call." The plan's `:384` says "Shipped default OFF… Conviction the lane is safe ON: 85%… it is the operator's."

The operator then asked for the fleet shape (find the limited accounts, list their panes, move all of them in parallel). The result replaced the architecture. `LIMIT_RECOVER_100P.md:933-942`: "superseded in shape by LIMIT_RECOVER_FLEET_V2… FLEET_V2 replaces it with the `lr_recon` reconciler." There was also an observed side effect: "all four went to the same account… piling them onto one account could push it into its own limit" (LR 04:18:45Z).

## Case 82 — agent-context-sync "is this deployable?" (19:37:44)

This was the first prompt of the session, so there was no prior claim. The response (19:39:06Z) quoted the README: "a design with measured probes. There is no implementation yet." This is not a post-claim hole: the operator's own picture of the project had drifted from the repo across sessions. The design was published 09-24 (session 810e8bd4), followed by launch-film sessions on 09-25. The whole implementation was then built in this session; the commits are dated 2026-09-29 16:30 −0500, after the ask.

## Case 83 — "No. … master 2.0 release" (20:32:26)

**Prior claim** (TM2 20:27:50Z): "run the full 2.0 program… 85%… **What changed:** the author has gone quiet on outside contributions. He hasn't replied to or reviewed any outside PR or issue since mid-June." The program was paced by the author's replies, with a 30-day-silence stop (20:31:03Z).

**Operator** (20:31:36Z): "We literally are in direct contenet with the original creator Josh… coworking together 1 on 1 in person… he will gladly approve." Then (20:32:26Z): "No. 100.00/100.00… master 2.0 release."

The agent had already been told on 09-29 at 01:21 that "the author did reply on 09-27 and invited PRs", yet at 20:27 it re-derived "gone quiet" from public GitHub. The correction had not carried across the recycle at 19:44, whose brief is TM2's first user record.

**Replan critic loop** (TM2; `c83after2.txt`):
- 03:04:40Z: "Rounds 1–5 found 37, then 26, 22, 17 and 14 distinct gaps… this round's blocker was introduced by the session's own previous fixes."
- 04:23:53Z: "Round 6 found 22… up from 14, so the loop has leveled off"; 04:24:17Z: "delete, rather than patch, the process machinery your build-everything-now ruling made unnecessary. That machinery is where about half of round 6's gaps came from."
- 09:22:43Z, the stop-rule decision: "9 critique rounds of about an hour each found 37, 26, 22, 17, 14, 22, 17, 11 and 14 verified gaps… about half are operational details, often introduced by the previous round's own fixes. A build session would hit and fix those in minutes… About 5 to 8 per round are things the build can't discover."
- 15:23:40Z: "Round 11… 22 verified gaps… The last three rounds each found 21 or 22."
- Operator (15:58:15Z): "decide whether the plan counts as finished once critics find zero gaps the build can't catch… Yes."
- 17:16:36Z: "Under the sorting test, only 5 of its 20 verified gaps are ones the build can't catch, down from 13 under the looser sorting." The category moved with how it was defined.
- 18:24:30Z, round 13, restricted to gaps the build can't catch, still found 16, "Several were real design changes: Design notes go to Josh as issues… Every user re-runs setup once after upgrading: that's the only way one of the four security fixes reaches existing installs… The ask to Josh gains two points."

**The release-methodology research** was triggered by the operator (00:57:58Z): "What is the 100th percentile… major version bump release… methodology… from leading examples?" It produced verified gaps that were folded into round 4 (01:29:14Z). One example is the transition-before-break bridge release (01:29:37Z). The original 2.0 research had asked only "how best-in-class projects present a major release" (TM1 01:38:36Z).

**Decision oscillation on the "four public sentences"**: redact at 78% (TM1 17:43:40Z), then redact at 85% (TM2 20:27:50Z), then leave at 80% (20:32:03Z, after the operator's context), then remove at 85% (21:14:51Z, after checking archives and finding 5 lines on main).

## Case 85 — agent-context-sync one-prompt setup (04:39:24)

- **Claim 1** (ACS 02:51:54Z): "👤 My side is done and landed… Good to close: yes. Nothing of mine is open." Deployment was defined as four manual steps from `docs/deploy/README.md`.
- **Operator** (03:23:19Z): "This seems like this needs to be a 'one prompt' setup… paste into Copilot CLI / Claude Code on the corporate side." Two sandbox validator agents then executed the prompt. Their findings (04:32:07Z): "The published repo didn't yet support the prompt… The Allow dialog can appear during the install, not only at the end… **Online-only files are downloaded, up to 1 GiB per folder per sync. The prompt previously said they weren't.** The 'done' check now reads launchd's exit code, so it can't pass without the background job actually running."
- **Claim 2** (04:32:07Z): "Good to close: yes. Nothing of mine is open."
- **Operator** (04:39:24Z): is the prompt set up to report back what went wrong?
- **Answer** (04:39:45Z): "No. Right now the prompt ends with a five-line summary… So a setup on the corporate Mac would teach us almost nothing." What followed was a setup-report plus friction log, five validator rounds, and prompt v6 (15:02:30Z).

## Cases 84, 86 and 87 — irrelevant, with pattern notes

- **84** (personal deadlines kickoff): not a completeness question. The operator's framing names a mechanism that feeds the loop elsewhere: "We have so many session that are 'complete for now, we will bring this up once its time' AND WE NEVER DO."
- **86** (cc-backlog master plan kickoff): no prior claim. It shows research perishing while it runs: "The run took about 12.6 hours, so the ledger moved in the meantime" (17:28:46Z); "Another 21 had closed on their own during the run" (18:37:25Z). The public-repo land gate refused the plan at land time (18:13:55Z), a constraint the research had not modeled.
- **87**: this workflow's own trigger prompt.

---

## Holes (after a prior completeness claim) and mechanisms

| ID | Hole | Mechanism (my judgment) | Materiality | Findable earlier |
|---|---|---|---|---|
| H1 | 20 consistency defects in the script-assembled plan v2 | The claim was certified on the ~40 component edits; the integrated artifact was never read after its last change | refinement | yes, desk |
| H2 | Rebase onto upstream v2.20 first; ASR tests, stored prompts, the Debug-build measurement and 80% of line refs are invalidated | A baseline premise, "build on the current fork", was settled silently by a freeze clause; the drift facts had been known since 09-27 21:06; the adversarial reviewers audited the plan's content, not its unstated premises | decision-changing | yes, desk |
| H3 | 15 silent recordings caused by upstream bug #956 | The upstream issue tracker was never a source; it was searched only after the operator's rebase question | refinement | yes, desk |
| H4 | "Author never replied" was false; he invited PRs on 09-27; the recommendation flipped from no at 90% to yes at 82% | A stale instrument (a message index built 09-24) was read as truth even though the tool warned it was stale | decision-changing | yes, desk |
| H5 | "You'd sign a licence agreement" was wrong; opening a PR accepts the CLA | A claim made from memory or inference, not checked against CONTRIBUTING | refinement | yes, desk |
| H6 | The operator wanted a full release program (roadmap, master PR, stacked PRs), not "upstream: yes or no" | The agent answered the narrow question it had filed; the operator's deliverable was never elicited | new-scope | only after the operator said it |
| H7 | "TrueMemory 2.0: bring EVERYTHING to 100th percentile" versus the 19-PR plan just declared finished | Scope escalated by the operator; "finished" was relative to a frame the agent chose | new-scope | only after the operator said it |
| H8 | An unfiled security advisory sat on a public-mirrored trunk, one lint-fix away from publication | The publication surface (the 3-hourly public mirror) was outside the research frame | decision-changing | yes, desk |
| H9 | Critic loop: 23/21/24/28 new blockers and majors, none repeated; 38 known gaps left | Each fix added new surface that the next critic attacked; an unbounded "find gaps" prompt always yields output; some gaps (Day-0 fork evidence) need building | refinement | only by building or probing |
| H10 | The first 2.0 run counted three dead critics as "no gaps" | An absent verdict was read as a clean verdict (quota-killed agents) | refinement | yes, desk |
| H11 | The published issue was in 4 places, not 2; the recommendation flipped from remove-folder to redact | The decision was made on a partial fact set with no pre-declared fact checklist | refinement | yes, desk |
| H12 | Limit-recover declared COMPLETE on n=1; production n=5 gave 1/4; the 09-29 incident showed a `set -e` bare-checkout death and an ownerless lock | Validated under unrepresentative conditions (a quiet box, a self-spawned pane); environmental states appear only in production | decision-changing | only by building or probing |
| H13 | "Zero human" was impossible by construction because auto-recover shipped OFF as the operator's call | An open decision was parked at 85% and never forced; "complete" was declared over an unruled gate | refinement | yes, desk |
| H14 | Fleet-parallel recovery was needed (many panes limited at once); the one-at-a-time drivers were superseded by the FLEET_V2 reconciler | The design frame was the single-session case; the fleet case (all panes on an account hit the limit together) was predictable but not modeled until the operator asked | decision-changing | yes, desk |
| H15 | The plan was built around "author unresponsive, pace by replies", but the operator had an in-person agreement with Josh; the program was reshaped and 10 of 38 gaps retired | Operator-private context was never elicited; a public proxy was used instead; the 09-27 invite correction was lost across the recycle | decision-changing | only after the operator said it |
| H16 | Replan critic loop: 37, 26, 22, 17, 14, 22, 17, 11, 14, 21, 22, 20, 16 over 13+ rounds; round 13 still found real design changes | No stop rule separated build-discoverable gaps from plan-only ones; fixes added machinery; the "uncatchable" category shifted with its definition (13 versus 5) | refinement | only by building or probing |
| H17 | Release-methodology exemplars (transition-before-break, bridge releases…) missing from the 2.0 plan | The original research question was framed as "presentation", not "methodology"; the operator reframed it | refinement | yes, desk |
| H18 | The public-sentences decision oscillated: redact 78%, redact 85%, leave 80%, remove 85% | Each ad-hoc re-check added facts; there was no fixed fact list and no operator-context elicitation first | refinement | yes, desk |
| H19 | The deploy was "done" as a 4-step human doc, but the operator needed an agent-drivable one-prompt setup | The consumer of the deliverable (an agent on a corporate Mac) was never established; the operator's standing one-command preference was not applied | new-scope | yes, desk |
| H20 | Docs claimed online-only files were not downloaded, but they were (up to 1 GiB); the done-check could pass without the job running | A claim checked by reading, not by executing; the sandbox execution found it | refinement | only by building or probing |
| H21 | The one-prompt setup had no friction or failure report from the real corporate run | The only real acceptance environment is out of reach, and no feedback instrument was designed for it; the operator added the requirement | new-scope | yes, desk |

## Patterns in this shard

1. **Unstated premises escape the critics.** The "what's missing" reviewers audit what the plan *says*. H2 (building on a stale base), H15 (author unresponsive), H14 (single-session frame) and H19 (a human is the installer) were all premises that no reviewer examined. Two of them had been settled silently by default: H2's freeze clause and H13's OFF default. Neither was raised as a decision with a conviction number.
2. **Critic loops do not converge; they generate.** Two independent 2.0 loops found 23→28 and 37→…→16 verified gaps a round over 4 and 13+ rounds. The sessions themselves report that fixes "add more machinery of its own… and the next round critiques that". Convergence arrived only with an operator-ruled stop rule ("zero gaps the build can't catch") and deletion of machinery. Even then the bucket moved with how it was defined.
3. **Operator-private context and scope are elicited late, and they are the biggest flips.** H6, H7, H15 and H19 each reshaped the plan. Each was revealed by the operator reacting to a claim, not by the agent asking at intake.
4. **Stale or absent instruments are read as truth.** A message index built four days earlier, whose staleness the tool printed (H4); dead critics read as "no gaps" (H10); a recycle brief that dropped a correction (H15).
5. **Integration and execution checks come after the claim.** The plan was assembled but never re-read (H1). Docs asserted behavior that execution refuted (H20). "Complete" rested on n=1 (H12). Every claim was certified on parts or on reasoning, not on the integrated artifact running in the target environment.
6. **Research perishes during long runs.** Upstream kept moving (H2), the ledger moved during a 12.6 h audit (case 86), and the author's GitHub state was re-read differently between turns (H15). A completeness claim has a shelf life that no transcript stated.
7. **Conviction numbers move by ±10–15 points on each ad-hoc check** (H4, H11, H18). This shows decisions were issued before their fact set was enumerated.
