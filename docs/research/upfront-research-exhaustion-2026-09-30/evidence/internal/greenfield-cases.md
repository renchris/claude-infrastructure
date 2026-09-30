# Greenfield case studies: why "100.00/100.00 complete" keeps reopening

Scope: the seven greenfield projects under `~/Development` named in the brief (all seven exist). Read-only.
Sources: each repo's git history, its tracked `docs/plans` + `docs/research`, the gitignored `.claude-plans/`
where present, and operator prompts mined from `~/.claude*/projects/*/*.jsonl`.
Scripts and raw extracts: `/tmp/rescomp/internal/gc_mine.py` (prompt census, output `gc_mine.json`),
`gc_replies.py` (the assistant's reply to each completeness ask, output `gc_replies.txt`),
`gc_selfcorr.py` (assistant self-correction phrases, output `gc_selfcorr.txt`), `gc_prompts.txt` (keyword-filtered
prompts from `/tmp/rescomp/prompts_dedup.json` for these cwds).

**Caveat on the transcript side:** retained transcripts for these projects start 2026-08-23 (sevenrooms-bridge)
at the earliest, so July work is visible only through git. The counts below come from regular expressions, so they
are lower bounds on a pattern, not a census of it.

## Answer first

**The upfront research phases were short (hours to about 2 days) and converged. The weeks come from what
happened *after* each "done":** defects that only contact with a compiler, production, a real tenant or a real
reader can reveal; a completeness axis that was never written down at intake, so each "are we 100%?" is
judged on a new axis; facts and intent the operator or a stakeholder supplied late; the world changing
under the plan; and dormant gaps while work waited on an operator step. The "are we done?" question is
itself the main audit trigger. Agents answer from recall, and asking makes them re-read, and the re-read finds the
next thing. In 3 of the 15 replies extracted, the reply says so in those words.

## Case table

| Project | First research → first usable/deploy | Calendar | Rounds / reopens after "done" | What caused each reopen (receipt) |
|---|---|---|---|---|
| **sevenrooms-bridge** (+ research in reso-web-app) | Research + scaffold 2026-07-20 (`reso-web-app docs/research/SIGNUP_TO_SEVENROOMS_AUTOMATION_RESEARCH.md` first commit 07-20; `bb42416` 07-20T00:20) → **live 2026-08-24T00:41Z** (operator brief `ee52fbd4…`, 2026-08-24T02:50; `2c3df13` "§H inverted on success — it went red the moment we went live") | 35 days, of which about 4 active: no commits in either repo 07-21..08-21 (`git log --format=%ad` counts: reso-web-app 21 on 07-20, then 2 on 08-22) | ≥5: (1) 08-22 state audit, 31 agents: "Two premises in the task framing are wrong" (`SEVENROOMS_PIPELINE_STATE_2026-08-22.md:22`). (2) 08-23 REFRAME: "item 1 is a MISSING CREDENTIAL, not a code defect" (`SEVENROOMS_PIPELINE_WORKLIST_2026-08-23.md:80`). (3) Post-live fixes: `3cab1ed` "56 checks and none asked whether the session was still alive", `b03a348` "going live silently turned every test record into a real guest", `2e25300` "could write into a real guestlist and never correct it". (4) 9-day session outage 08-26→09-04 (operator brief `1bd8904c`, 2026-09-04T19:04). (5) Laptop dependency: new research 09-25 → Lambda renewer live 09-26 (`LAPTOP_INDEPENDENCE.md`, `5d7ebf0`) | Contact with production · a runtime dependency (the laptop, the session lifetime) not in the 07-20 plan (grep for laptop, sleep, session expiry in the 07-20 plan: only `:266` "operator's warm session was still live") · a missing credential the research never inventoried · the insight brief was "judged lacking **twice**" and then restarted (`SEVENROOMS_MIRROR.md:349-353`) |
| **voiceink**: enhancement quota resilience | Bake-off/research 09-13 20:47 (`ee6bbbe0`) → plan signed off 2026-09-14 (sign-off prompt `ba08cab8` 19:25Z) → **live 09-14 17:30 CDT** (`.claude-plans/ENHANCEMENT_QUOTA_RESILIENCE.md` execution log: "app restarted … new pid at 17:30:04") | about 1 day | 3 reading passes + 1 contact pass. Plan-measured convergence: new defects **10 → 7 → 2** per pass, about 2 corrections per pass (`ENHANCEMENT_QUOTA_RESILIENCE.md:1413-1426`). Contact then found **D22-D24**, "not in the 21" (`:1642-1656`), cut two plan items (`:1621-1640`), and found a sibling repo's declared end state that research never searched (execution log, item 7) | Code contact (a compiler, running code) · an adversarial question at sign-off: "Item 1e above was found by this same question" (`:1234-1236`) · a probe the permission classifier refused, so 4a/4b shipped at 93%/85% (`:1245-1253`) · the in-product measurement (S7) waits on the operator's own dictations |
| **voiceink**: Willow latency parity | Research 09-27 (`9660e8ec`) → plan v1 09-27, v2 and v3 09-28, W1 landed 09-28 (`58b823ae`) → **W2/W3 not deployed** (last commit `9d2dbc2c` 09-28) | 3+ days, open | 3 plan versions in 1 day plus a 20-defect assembly fix (`d0196660` "20 assembly defects from a fresh review") | v2: an "8-lane verification … compile verification … completeness critic" changed the ASR choice, the hedge design and Phase 0 (`LATENCY_WILLOW_PARITY.md:262-269`). v3: **upstream moved** to v2.20, "Rebasing first changes this plan's content, not just its anchors", "155 edits", a toolchain constraint (Xcode 26.4 vs Sequoia) (`:63`, `:270-274`) |
| **agent-context-sync** | Design + receipts 2026-09-24 09:36 (`9239b19`) → implementation 09-29 → running on the dev Mac 09-29/30 (`4eb576f`) → **corporate install is an operator step dated Wed 2026-09-30** (`docs/plans/implementation.md` rollout table) | 6 days to the dev Mac; corporate target still open | Design → readiness audit: **46 verified findings**, 48 `CORRECTED` markers in the design doc (`f483625`; `grep -c CORRECTED docs/design/agent-context-sync.md` → 48). Setup prompt went through v4 → v5 → v6 inside about a day, reviewed from real runs (`docs/deploy/setup-feedback.md:199-205`). Hero film: 3 operator-verdict rounds on 09-24 (`7eec6f6`, `6ea5489`) | The world changed: "sharedWithMe deprecation (Nov 2026)", "Teams channel delta no longer documented" (`f483625` body) · a measurement that did not hold ("st_blocks is not a dataless test") · corporate controls (C15) added only at the audit (`eab43e4`) · the 5-day gap 09-24 → 09-29 was spent on the film, not on research |
| **natural-text-to-voice-extension** (2026-09 upgrade) | Upgrade research 2026-09-23 17:01 (`11b063a`) → v1.5.0 the same evening (`3ca0b2e`) → 1.5.1 09-24 (`3cd621a`) → **submitted to the Chrome Web Store 2026-09-25** (`docs/publishing/CHROME_WEB_STORE.md:37`) | about 2 days | Review rounds **capped in advance**: "Round 1 of … at most 2" and "This is round 2 of 2, the last" (`docs/research/2026-09-upgrade/README.pyramid-worklog.md:603-604, 698`). One mid-flight decision (loudness limiter) was researched A-D and handed to the operator at **80%** (`limiter-decision/README.md:1-9`) | This is the positive control: a bounded round count plus an explicit conviction number shipped in 2 days. Later rounds (the launch film, 09-26/27) are taste loops, not reopened research |
| **reso-web-app** (stack/latency + visual) | Deps/stack research 2026-08-26 → **live the same day** (`d0630e1c` reply 2026-08-26T20:14: "Your site is live on the new stack"). Visual: `HUMAN_SEO_VISUAL_REBUILD.md` W3 landed 08-25. `VISUAL_100P_REBUILD.md` researched 09-21, "Implementation not started" (`:7-8`) | Stack: 1 day. Visual 100p: 9+ days, not started | Deps plan: 31 revisions in 3 days (`git log -- docs/plans/GROUND_UP_DEPS_PERF_UPGRADE.md`); sections headed "THIS SECTION WAS WRONG" (`:289`), "CORRECTION … that ceiling is DOCUMENTATION, not a gate" (`:327`), "Prior measurements that must be re-litigated" (`:266`), "THREE CORRECTIONS to the RUM section" (`:1318`), an outage the wave uncovered (`:1049`). `FOUNDATIONS_ANSWER` is marked PROVISIONAL, "a patch around a hole", superseded by `THE_ANSWER` (`FOUNDATIONS_ANSWER_2026-08-26.md:3-8`). Visual: both previews rejected; the 8-agent re-research was stopped by the user (prompt `620fd815` 2026-09-22T05:36) | A baseline measurement redirected the plan (`:27` "it redirects this plan") · a hung workflow was synthesized as an answer · verification with the wrong instrument ("I reproduced the agent's **method**, not its **conclusion**", reply 08-26T20:14) · briefs asked the wrong question: "A fan-out agrees with itself when its briefs share a premise" (`VISUAL_100P_REBUILD.md:497-507`) · a completeness ask found H15 not done ("Correcting my earlier '100%'", reply 08-27T20:26) |
| **fde-endpoint-business-case** | Research corpus + email rev 6.0 2026-09-16 16:40 (`8fcdcb6`) → rev 9.0 2026-09-17 14:53 (`8cfa35e`); still "DRAFT, not sent" (`EMAIL_DRAFT.md:3`) | about 1 day of work; sending not recorded | **23 revision headings** (`grep -cE '^#{2,3} Revision' EMAIL_DRAFT.pyramid-worklog.md` → 23). Adversarial passes: rev 5.0 "DO NOT SEND"; rev 6.0 used 64 agents, 88 findings, 26 survived, "DO NOT SEND" again (`worklog` Revision 5.0/6.0) | Facts arriving late from the operator: 4 are named as the operator's (`EMAIL_DRAFT.md:4`): client-owned laptops (rev 7.2, "why was this concept introduced?", prompt `fa6a131b` 09-17T04:52), both agents in scope (7.3), one path only (8.0) · the external reader's constraint "5 sentences max" came last (rev 9.0) · adversarial passes with no stop floor kept finding new defects |
| **mac-bootstrap** | First commit **and** first release 2026-09-11 (`ef889f5`, `5c2a8e6`) → **16 release pins in 5 days** (`git log --format=%s | grep -ciE 'pin the release|point the entry point'` → 16) | Usable 09-11; "complete" still open 09-16 | Completeness research 09-15 (14 reports, 4 dry runs): verdict **"No. It is correct in what it does … It is not complete"**, with 7 consolidated P0s (`.claude-plans/research/blueprint-completeness-2026-09-15/SYNTHESIS.md`); 21 gaps re-checked (`TOOLS_COMPLETENESS.md`). `Scope (grown)` from a peer's recheck (`ONE_COMMAND_INSTALL.md:256`) | The completeness axis was never pinned: correctness vs "blueprint of this laptop" vs no public downloads vs no cloud AI. The operator restated intent on 09-16: "This whole point of this repo was 'all the select tools i use here'" (prompt `eda3a683` 2026-09-16T02:52) · the lead retracted 3 of its own dry-run findings (reply 09-16T02:43) |

## Operator frustration signals (verbatim, with receipts)

Census (`gc_mine.py`; genuine prompts only, machine briefs excluded):

| Project | prompts | completeness asks | frustration-pattern hits |
|---|---|---|---|
| sevenrooms-bridge | 100 | 8 | 15 |
| voiceink | 47 | 7 | 9 |
| reso-web-app | 33 | 6 | 3 |
| natural-text-to-voice-extension | 32 | 4 | 0 |
| fde-endpoint-business-case | 29 | 0 | 2 |
| mac-bootstrap | 21 | 3 | 4 |
| agent-context-sync | 8 | 3 | 1 |

The ones that name the mechanism directly:

- reso-web-app, `d0630e1c`, 2026-08-26T19:34: *"To affirm, are we re-running incomplete/failed research in full, we are not simply trying to patch and deduce around the missing holes?"*
- voiceink, `ba08cab8`, 2026-09-14T19:02 and 19:25: *"Have you exhaustively researched to come back with a 100.00/100.00 …?"*, then *"Do you deem it 100.00/100.00 … If so, I approve"*. The plan records that the answer was **no** each of the three times and that the operator approved "on that description rather than on a number" (`ENHANCEMENT_QUOTA_RESILIENCE.md:1495-1501`).
- voiceink, `61853387`, 2026-09-14T05:05: *"ALWAYS fix until 100.00/100.00 … including all new found work, follow-ons, loose-ends. Do we need to modify our CLAUDE.md or stop hook?"*
- voiceink, `82354751`, 2026-09-12T19:12: *"So not 'yet' what are we waiting for? If we need more exhaustive research, do so now."*
- voiceink, `82354751`, 2026-09-12T02:14: *"'I manufactured that step.' This happens a lot. Almost everytime I feel."*
- agent-context-sync, `46d14e14`, 2026-09-29T19:40: *"non-action is not a choice … at some actionable timeframe/deadline and not some indefinite future/never because of non-concrete follow-on work/todos."*
- mac-bootstrap, `eda3a683`, 2026-09-16T02:52: *"This whole point of this repo was 'all the select tools i use here'"*.
- sevenrooms-bridge: the insight work was "judged … LACKING, twice" (brief `ed403d43`, 2026-08-26T08:24), plus *"a lot of 'insights' is just deduction … this doesnt actuate any actual insights"* (2026-08-27T03:56).
- fde, `fa6a131b`, 2026-09-17T04:52: *"why was this concept introduced? Client-side laptops are ultimately bought and managed by client."*
- Research fan-outs stopped by the user mid-run: reso-web-app 8 agents (09-22T05:36), mac-bootstrap 6 agents (09-16T15:19), voiceink 4 teammates (09-14T22:39), sevenrooms-bridge 2 (09-21T16:36), mac-bootstrap 2 (09-14T02:50).

The assistant's own words when asked "are we done?" (`gc_replies.txt`, `gc_selfcorr.txt`):

- reso-web-app, 2026-08-27T20:26: *"your question caught something … **Correcting my earlier '100%'** … Asking made me re-read my own work instead of recalling it, and two things were wrong."*
- voiceink, 2026-09-14T19:45: *"your question caught something that would have been lost"* (5 of 9 research artifacts existed only in `/tmp`).
- voiceink plan `:1234`: *"Asked at sign-off whether this was exhaustively researched, the honest answer was no … Item 1e above was found by this same question."*
- sevenrooms-bridge, 2026-08-23T19:41: *"**No.** Engineering-complete, but the pipeline has never written to SevenRooms."* Then at 21:26: *"I was wrong to say the code is 'running in production.' Three real loose ends."*
- Self-correction phrases per project ("I was wrong", "my headline finding was wrong", "correcting my earlier", …): reso-web-app 23, sevenrooms-bridge 13, voiceink 9, mac-bootstrap 2, natural-text-to-voice 1, agent-context-sync 0, fde 0.

## The recurring mechanisms

1. **A reading-only research phase has a ceiling that more reading cannot raise.** The voiceink plan measured its
   own convergence (10 → 7 → 2 new defects per pass) and stated the limit: *"every pass so far has been a reading
   … the entire class of error that only a compiler or a running app can reveal is untouched"* (`:1427-1431`).
   Contact then produced D22-D24. The same shape shows up in sevenrooms-bridge (a preflight "went red the moment we
   went live", `2c3df13`; test records became real guests, `b03a348`), agent-context-sync (46 audit findings on a
   design already called researched) and reso-web-app (a baseline "redirects this plan"). **What a no-take-backs
   method needs:** declare the contact-only residual at sign-off as expected work, not as a reopen. Pull cheap
   contact (a compile spike, a production probe, a real-tenant probe) into the research phase so it is spent
   there.

2. **The completeness axis is not written down at intake, so "100%" is judged on a new axis each time.**
   mac-bootstrap: "correct in what it does" and "not complete" at the same moment, over four axes nobody had
   enumerated (`SYNTHESIS.md` Verdict), and then the operator's "whole point". sevenrooms-bridge: engineering-complete,
   then zero-human, then laptop-independent, each a later reopen. reso-web-app: "the task is complete, hazard H15 is
   not". **Fix:** a frozen acceptance matrix (every axis, each with its check command) before any research wave.
   A later "are we 100%?" is then a diff against it, and a new axis is logged as scope growth, not as a
   research miss.

3. **The "are we done?" question is the only thing that triggers a re-audit.** Closes are asserted from recall.
   The question forces a re-read, and the re-read finds the next item (three verbatim admissions above, plus 1e in
   voiceink). So each re-ask manufactures the next "one small other thing". **Fix:** run the adversarial re-read
   as a mandatory step *before* the first completeness claim, with a fixed scope (the acceptance matrix), so the
   question has nothing new to trigger.

4. **Intent and facts arrive late, and fan-outs amplify a wrong premise.** fde has 4 operator-supplied facts and a
   stakeholder's 5-sentence cap, all after rev 6.0. reso visual: 8 axes were all briefed "what would 100th-percentile
   look like", and none "what is the smallest change to reso's own system"; *"A fan-out agrees with itself when
   its briefs share a premise"* (`VISUAL_100P_REBUILD.md:505-507`). The sevenrooms insight brief was lacking twice
   until "the operator was asked directly what 'not lacking' means" (`SEVENROOMS_MIRROR.md:353`). **Fix:** an
   intake interview that elicits the audience, constraints, owned facts and the definition of "not lacking" before
   wave 1, and a critic that checks the briefs' shared premise against the operator's words.

5. **The world moves during and after research.** voiceink upstream v2.20 forced a 155-edit re-anchor that changed
   the plan's *content* (`LATENCY_WILLOW_PARITY.md:63`). Microsoft deprecated `sharedWithMe` and dropped the Teams
   delta docs between the 09-24 design and the 09-29 audit (`f483625`). An AWS support matrix was stale
   (reply 08-26T08:28). **Fix:** stamp every external fact with a date and a re-check command, and re-run those
   checks at the implementation gate. This is not a research miss, and it should not be counted as one.

6. **Research instruments with no stopping rule.** fde's adversarial passes returned DO NOT SEND twice (rev 5.0,
   6.0: 64 agents, 88 findings, 26 survived). An adversarial lens over an unbounded space always finds something.
   The positive control is natural-text-to-voice's pre-declared "round 2 of 2, the last", which reached store
   submission in about 2 days, and the voiceink curve, which gave a measured basis to stop. **Fix:** declare the
   round cap and the convergence stop (new findings per pass below a threshold, severity-weighted) before the
   first pass.

7. **A partial or failed research run is synthesized as an answer, then retracted.** `FOUNDATIONS_ANSWER` came
   from a workflow that hung at 4/5 with no red team ("a patch around a hole"). "I reproduced the agent's method,
   not its conclusion." A preview was verified as a local file, never at the published URL
   (`VISUAL_100P_REBUILD.md:470-478`). mac-bootstrap retracted 3 dry-run findings. **Fix:** a slot that failed or
   hung blocks synthesis, and every verification must use an instrument independent of the claim.

8. **Runtime and operational dependencies sit outside the research frame.** The 07-20 SevenRooms plan never
   modeled session lifetime or where the process lives. The result was a 9-day outage (08-26→09-04) and a second
   research program (laptop independence, 09-25). **Fix:** make "where does it run, what keeps it alive, what
   expires, who re-authenticates" a mandatory axis in the acceptance matrix.

9. **Calendar time is dominated by dormancy and operator-owned steps, not by research.** sevenrooms-bridge was idle
   33 of 35 days. agent-context-sync spent 5 days between design and implementation, mostly on the film. The corporate
   install of agent-context-sync is an operator step. VoiceInk's S7 waits on the operator's own dictations. The
   visual 100p plan was researched 09-21 and was still not started 9+ days later. **Fix:** put a dated owner on
   every operator gate inside the plan, the way `agent-context-sync/docs/plans/implementation.md`'s rollout
   table does, so dormant time is visible rather than read as unfinished research.

## Bottom line for the methodology

In these seven cases, upfront research was never the long pole: each research phase took 1 to 2 days and was
honest about its residual when asked. What turned days into weeks was (a) completeness axes that were never
enumerated, so each ask found a new one; (b) no pre-declared stop rule for adversarial rounds; (c) contact-only
defects treated as research failures instead of as a planned residual; (d) late intent and facts; and
(e) dormant operator gates. A "no take-backs" protocol has to freeze (a) and (b) at intake, budget (c)
explicitly, front-load (d) as an interview, and date (e).
